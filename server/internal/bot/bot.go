// Package bot implements the Telegram long-polling bot: free-text entry with
// alias learning, summaries, /undo and /categories. Every reply is localized
// into English, Russian or Uzbek by internal/i18n.
//
// It writes through the store's local-write path, which marks rows dirty and
// fires the write hook, so the Drive sync engine publishes each entry to the
// phone on its next (3 s-debounced) pass. The bot itself contains no sync code.
package bot

import (
	"context"
	"errors"
	"log"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	tgbot "github.com/go-telegram/bot"
	"github.com/go-telegram/bot/models"

	"github.com/xensa/tally/internal/i18n"
	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
)

// pendingEntry is a parsed message waiting for a category pick.
type pendingEntry struct {
	AmountMinor int64
	Kind        string
	Word        string
	Note        string
}

// Bot wraps the Telegram bot and its dependencies.
type Bot struct {
	st      *store.Store
	bundle  *i18n.Bundle
	allowed map[int64]struct{}
	tg      *tgbot.Bot
	// loc is the calendar the /today, /week and /month boundaries are cut on.
	// The app cuts them at LOCAL midnight, so a bot pinned to UTC would report
	// a different window than the phone's Home screen for the same data.
	loc *time.Location

	mu      sync.Mutex
	pending map[int64]pendingEntry // keyed by telegram user id
}

// session is the per-update locale context: which language to answer in and
// which currency to render amounts with. Both come from the same settings read,
// so a reply can never mix a stale currency with a fresh language.
type session struct {
	p        *i18n.Printer
	currency string
}

// New creates the bot (long polling). allowedIDs is the allow-list of
// Telegram user ids; everyone else is ignored. loc is the timezone the
// summary periods are cut in (nil = UTC).
func New(token string, allowedIDs []int64, st *store.Store, loc *time.Location) (*Bot, error) {
	bundle, err := i18n.New()
	if err != nil {
		return nil, err
	}
	if loc == nil {
		loc = time.UTC
	}
	b := &Bot{
		st:      st,
		bundle:  bundle,
		loc:     loc,
		allowed: make(map[int64]struct{}, len(allowedIDs)),
		pending: make(map[int64]pendingEntry),
	}
	for _, id := range allowedIDs {
		b.allowed[id] = struct{}{}
	}
	tg, err := tgbot.New(token, tgbot.WithDefaultHandler(b.handleUpdate))
	if err != nil {
		return nil, err
	}
	b.tg = tg
	return b, nil
}

// Run starts long polling and blocks until ctx is cancelled.
func (b *Bot) Run(ctx context.Context) { b.tg.Start(ctx) }

func (b *Bot) isAllowed(userID int64) bool {
	_, ok := b.allowed[userID]
	return ok
}

// session resolves the reply language per the contract —
// settings.language → Telegram user.language_code → English — and reads the
// currency in the same pass. A settings read failure still yields a usable
// session so the user gets an answer.
func (b *Bot) session(langCode string) session {
	st, err := b.st.Settings()
	if err != nil {
		log.Printf("bot: read settings: %v", err)
		return session{p: b.bundle.For("", langCode), currency: "USD"}
	}
	return session{p: b.bundle.For(st.Language, langCode), currency: st.Currency}
}

func (b *Bot) send(ctx context.Context, chatID int64, text string, markup models.ReplyMarkup) {
	_, err := b.tg.SendMessage(ctx, &tgbot.SendMessageParams{
		ChatID:      chatID,
		Text:        text,
		ReplyMarkup: markup,
	})
	if err != nil {
		log.Printf("bot: send message: %v", err)
	}
}

func (b *Bot) handleUpdate(ctx context.Context, _ *tgbot.Bot, update *models.Update) {
	switch {
	case update.CallbackQuery != nil:
		b.handleCallback(ctx, update.CallbackQuery)
	case update.Message != nil && update.Message.Text != "":
		b.handleMessage(ctx, update.Message)
	}
}

func (b *Bot) handleMessage(ctx context.Context, msg *models.Message) {
	if msg.From == nil {
		return
	}
	userID := msg.From.ID
	text := strings.TrimSpace(msg.Text)
	if !b.isAllowed(userID) {
		// Strangers get a polite rejection on /start only; everything else
		// is ignored.
		if strings.HasPrefix(text, "/start") {
			s := b.session(msg.From.LanguageCode)
			b.send(ctx, msg.Chat.ID, s.p.T("unauthorized"), nil)
		}
		return
	}
	s := b.session(msg.From.LanguageCode)
	if strings.HasPrefix(text, "/") {
		b.handleCommand(ctx, msg.Chat.ID, text, s)
		return
	}
	b.handleEntry(ctx, msg.Chat.ID, userID, text, s)
}

func (b *Bot) handleCommand(ctx context.Context, chatID int64, text string, s session) {
	cmd := strings.Fields(text)[0]
	if at := strings.Index(cmd, "@"); at > 0 {
		cmd = cmd[:at]
	}
	now := time.Now().In(b.loc)
	switch cmd {
	case "/start":
		b.send(ctx, chatID, s.p.T("start"), nil)
	case "/today":
		from, to := dayRange(now)
		title := s.p.Tf("summary_today", map[string]any{"Date": s.p.Date(from)})
		b.sendSummary(ctx, chatID, title, from, to, s)
	case "/week":
		from, to := weekRange(now)
		title := s.p.Tf("summary_week", map[string]any{
			"From": s.p.Date(from),
			"To":   s.p.Date(to.AddDate(0, 0, -1)), // the range is half-open
		})
		b.sendSummary(ctx, chatID, title, from, to, s)
	case "/month":
		from, to := monthRange(now)
		title := s.p.Tf("summary_month", map[string]any{"Month": s.p.MonthYear(from)})
		b.sendSummary(ctx, chatID, title, from, to, s)
	case "/undo":
		b.handleUndo(ctx, chatID, s)
	case "/categories":
		b.handleCategories(ctx, chatID, s)
	default:
		b.send(ctx, chatID, s.p.T("unknown_command"), nil)
	}
}

// displayName applies the contract's seed-name rule: a seed category is shown
// translated only while the user has not renamed it; a renamed one displays
// verbatim in every language.
func displayName(p *i18n.Printer, c model.Category) string {
	if store.IsUnrenamedSeed(c) {
		return p.SeedName(c.Name)
	}
	return c.Name
}

// label is the emoji + display name pair used in replies and keyboards.
func label(p *i18n.Printer, c model.Category) string {
	return c.Emoji + " " + displayName(p, c)
}

// candidates pairs each category with every name it answers to, so matching
// accepts the canonical English name and each supported language's translation.
func candidates(bundle *i18n.Bundle, cats []model.Category) []namedCategory {
	out := make([]namedCategory, 0, len(cats))
	for _, c := range cats {
		names := []string{c.Name}
		if store.IsUnrenamedSeed(c) {
			names = append(names, bundle.SeedNameVariants(c.Name)...)
		}
		out = append(out, namedCategory{Cat: c, Names: names})
	}
	return out
}

func (b *Bot) sendSummary(ctx context.Context, chatID int64, title string, from, to time.Time, s session) {
	sum, err := b.st.PeriodSummary(from, to)
	if err != nil {
		log.Printf("bot: summary: %v", err)
		b.send(ctx, chatID, s.p.T("error_summary"), nil)
		return
	}
	b.send(ctx, chatID, renderSummary(s.p, s.currency, title, sum), nil)
}

func (b *Bot) handleUndo(ctx context.Context, chatID int64, s session) {
	p := s.p
	t, err := b.st.LastTransaction()
	if errors.Is(err, store.ErrNotFound) {
		b.send(ctx, chatID, p.T("undo_nothing"), nil)
		return
	}
	if err != nil {
		log.Printf("bot: undo lookup: %v", err)
		b.send(ctx, chatID, p.T("error_undo"), nil)
		return
	}
	if err := b.st.SoftDeleteTransaction(t.ID, time.Now().UTC().UnixMilli()); err != nil {
		log.Printf("bot: undo delete: %v", err)
		b.send(ctx, chatID, p.T("error_undo"), nil)
		return
	}
	var cat *model.Category
	if found, err := b.st.GetCategory(t.CategoryID); err == nil {
		cat = &found
	}
	b.send(ctx, chatID, renderUndo(p, s.currency, t, cat), nil)
}

func (b *Bot) handleCategories(ctx context.Context, chatID int64, s session) {
	p := s.p
	cats, err := b.st.ListCategories("")
	if err != nil {
		log.Printf("bot: list categories: %v", err)
		b.send(ctx, chatID, p.T("error_categories"), nil)
		return
	}
	b.send(ctx, chatID, renderCategories(p, cats), nil)
}

// handleEntry processes a free-text transaction message.
func (b *Bot) handleEntry(ctx context.Context, chatID, userID int64, text string, s session) {
	p := s.p
	entry, err := ParseMessage(text, i18n.CurrencyExp(s.currency))
	if err != nil {
		b.send(ctx, chatID, p.T("hint_amount"), nil)
		return
	}

	if entry.CategoryWord != "" {
		cat, err := b.resolveCategory(entry.CategoryWord, entry.Kind)
		if err != nil {
			log.Printf("bot: resolve category: %v", err)
			b.send(ctx, chatID, p.T("error_generic"), nil)
			return
		}
		if cat != nil {
			b.logTransaction(ctx, chatID, entry.AmountMinor, entry.Kind, entry.Note, *cat, s)
			return
		}
	}

	// No category word or no confident match → keyboard.
	b.mu.Lock()
	b.pending[userID] = pendingEntry{
		AmountMinor: entry.AmountMinor,
		Kind:        entry.Kind,
		Word:        entry.CategoryWord,
		Note:        entry.Note,
	}
	b.mu.Unlock()

	kb, err := b.categoryKeyboard(entry.Kind, entry.CategoryWord, p)
	if err != nil {
		log.Printf("bot: keyboard: %v", err)
		b.send(ctx, chatID, p.T("error_generic"), nil)
		return
	}
	prompt := p.Tf("pick_category", map[string]any{
		"Amount": p.MoneySigned(signedMinor(entry.Kind, entry.AmountMinor), s.currency),
	})
	b.send(ctx, chatID, prompt, kb)
}

// resolveCategory implements alias → exact → prefix → fuzzy matching against
// non-deleted categories of the given kind, in every supported language.
func (b *Bot) resolveCategory(word, kind string) (*model.Category, error) {
	w := strings.ToLower(word)
	if id, ok, err := b.st.GetAlias(w); err != nil {
		return nil, err
	} else if ok {
		cat, err := b.st.GetCategory(id)
		if err == nil && cat.DeletedAtMs == nil && cat.Kind == kind {
			return &cat, nil
		}
		if err != nil && !errors.Is(err, store.ErrNotFound) {
			return nil, err
		}
	}
	cats, err := b.st.ListCategories(kind)
	if err != nil {
		return nil, err
	}
	return matchCategory(w, candidates(b.bundle, cats)), nil
}

// categoryKeyboard builds the inline keyboard of one kind's categories,
// two per row, plus a `➕ New: "<word>"` button when word is non-empty.
// Labels are localized; callback data stays tiny: the category id, or "new".
func (b *Bot) categoryKeyboard(kind, word string, p *i18n.Printer) (*models.InlineKeyboardMarkup, error) {
	cats, err := b.st.ListCategories(kind)
	if err != nil {
		return nil, err
	}
	var rows [][]models.InlineKeyboardButton
	var row []models.InlineKeyboardButton
	for _, c := range cats {
		row = append(row, models.InlineKeyboardButton{
			Text:         label(p, c),
			CallbackData: c.ID,
		})
		if len(row) == 2 {
			rows = append(rows, row)
			row = nil
		}
	}
	if len(row) > 0 {
		rows = append(rows, row)
	}
	if word != "" {
		rows = append(rows, []models.InlineKeyboardButton{{
			Text:         p.Tf("button_new_category", map[string]any{"Word": word}),
			CallbackData: "new",
		}})
	}
	return &models.InlineKeyboardMarkup{InlineKeyboard: rows}, nil
}

func (b *Bot) handleCallback(ctx context.Context, q *models.CallbackQuery) {
	// Always answer so the client stops the spinner.
	if _, err := b.tg.AnswerCallbackQuery(ctx, &tgbot.AnswerCallbackQueryParams{CallbackQueryID: q.ID}); err != nil {
		log.Printf("bot: answer callback: %v", err)
	}
	userID := q.From.ID
	if !b.isAllowed(userID) {
		return
	}
	chatID := userID // single-user bot lives in the private chat
	s := b.session(q.From.LanguageCode)
	p := s.p

	b.mu.Lock()
	pend, ok := b.pending[userID]
	if ok {
		delete(b.pending, userID)
	}
	b.mu.Unlock()
	if !ok {
		b.send(ctx, chatID, p.T("nothing_pending"), nil)
		return
	}

	// Drop the keyboard from the prompt message, best effort.
	if q.Message.Message != nil {
		_, _ = b.tg.EditMessageReplyMarkup(ctx, &tgbot.EditMessageReplyMarkupParams{
			ChatID:    q.Message.Message.Chat.ID,
			MessageID: q.Message.Message.ID,
		})
	}

	var cat model.Category
	if q.Data == "new" {
		if pend.Word == "" {
			b.send(ctx, chatID, p.T("new_category_needs_word"), nil)
			return
		}
		created, err := b.createCategory(pend.Word, pend.Kind)
		if err != nil {
			log.Printf("bot: create category: %v", err)
			b.send(ctx, chatID, p.T("error_create_category"), nil)
			return
		}
		cat = created
	} else {
		found, err := b.st.GetCategory(q.Data)
		if err != nil || found.DeletedAtMs != nil {
			b.send(ctx, chatID, p.T("category_gone"), nil)
			return
		}
		// Old keyboards stay tappable in chat history; a stale tap must not
		// attach an entry (or learn an alias) across kinds.
		if found.Kind != pend.Kind {
			b.send(ctx, chatID, p.Tf("category_wrong_kind", map[string]any{
				"Category": label(p, found),
				"Kind":     p.T(kindMessageID(found.Kind)),
			}), nil)
			return
		}
		cat = found
	}

	// Learn the alias so next time it is zero taps. The word is stored as the
	// user typed it, so a Russian alias keeps working after a language switch.
	if pend.Word != "" {
		if err := b.st.SetAlias(strings.ToLower(pend.Word), cat.ID); err != nil {
			log.Printf("bot: save alias: %v", err)
		}
	}
	b.logTransaction(ctx, chatID, pend.AmountMinor, pend.Kind, pend.Note, cat, s)
}

// kindMessageID maps a transaction kind to its catalog id.
func kindMessageID(kind string) string {
	if kind == model.KindIncome {
		return "kind_income"
	}
	return "kind_expense"
}

// capitalizeFirst upper-cases the first rune of word (UTF-8 safe: byte
// slicing would corrupt multi-byte first letters, e.g. Cyrillic).
func capitalizeFirst(word string) string {
	r, size := utf8.DecodeRuneInString(word)
	if r == utf8.RuneError && size <= 1 {
		return word
	}
	return string(unicode.ToUpper(r)) + word[size:]
}

// createCategory makes a new category named after word (capitalized). The name
// is user data, so it is stored verbatim and never localized afterwards.
func (b *Bot) createCategory(word, kind string) (model.Category, error) {
	maxSort, err := b.st.MaxSortOrder(kind)
	if err != nil {
		return model.Category{}, err
	}
	name := capitalizeFirst(word)
	c := model.Category{
		ID:          newUUID(),
		Name:        name,
		Emoji:       "🏷️",
		Color:       "#8E8E93",
		Kind:        kind,
		SortOrder:   maxSort + 1,
		UpdatedAtMs: time.Now().UTC().UnixMilli(),
	}
	if err := b.st.InsertCategory(c); err != nil {
		return model.Category{}, err
	}
	return c, nil
}

// logTransaction inserts the transaction (source "telegram") and sends the
// contract success reply, localized:
//
//	✅ −250,00 ₽ • 🛒 Продукты — 3 450,00 за месяц
func (b *Bot) logTransaction(ctx context.Context, chatID int64, amountMinor int64, kind, note string, cat model.Category, s session) {
	p := s.p
	// Stored instants are always UTC; only the reported period is cut on the
	// configured calendar.
	now := time.Now().UTC()
	t := model.Transaction{
		ID:          newUUID(),
		Kind:        kind,
		AmountMinor: amountMinor,
		CategoryID:  cat.ID,
		Note:        note,
		OccurredAt:  now.Format(model.CanonicalUTC),
		Source:      model.SourceTelegram,
		CreatedAtMs: now.UnixMilli(),
		UpdatedAtMs: now.UnixMilli(),
	}
	if err := b.st.InsertTransaction(t); err != nil {
		log.Printf("bot: insert transaction: %v", err)
		b.send(ctx, chatID, p.T("error_save"), nil)
		return
	}
	from, to := monthRange(now.In(b.loc))
	monthTotal, err := b.st.CategoryPeriodTotal(cat.ID, from, to)
	if err != nil {
		log.Printf("bot: month total: %v", err)
	}
	b.send(ctx, chatID, renderEntrySaved(p, s.currency, kind, amountMinor, monthTotal, cat), nil)
}
