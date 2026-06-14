"""
Anyong Bot v2.0 - Telegram Work-Management Bot
===============================================
Dual-bot architecture: runs two independent Telegram bots
(TOKEN / TOKEN2) in a single process with shared PostgreSQL storage,
connection pooling, graceful shutdown, and a keep-alive HTTP server.

Features
--------
- Check-in / check-out / break / return with timestamped logging
- Commission calculator (fan 30 % / staff 13 %)
- Script library (CRUD via inline buttons)
- Warning-clip library (CRUD)
- /summary   - daily work summary with hours
- /ranking   - monthly check-in leaderboard
- /export    - CSV export of personal work logs
- /broadcast - admin broadcast (ADMIN_IDS env var)
- /stats     - bot-wide statistics
- /profile   - personal stats card
- /reminder  - toggle auto-checkout reminder
- Pagination for scripts & clips
- Robust error handling & retry decorator
"""

from __future__ import annotations

import asyncio
import csv
import io
import logging
import os
import re
import signal
import sys
import threading
import time
from contextlib import contextmanager
from datetime import datetime
from functools import wraps
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

import psycopg2
import psycopg2.pool
from zoneinfo import ZoneInfo

from telegram import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    MessageEntity,
    ReplyKeyboardMarkup,
    ReplyKeyboardRemove,
    Update,
)
from telegram.constants import ParseMode
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    ConversationHandler,
    MessageHandler,
    filters,
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger("anyong")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
TOKEN: str = os.environ["TOKEN"]
TOKEN2: str = os.environ.get("TOKEN2", "")
DATABASE_URL: str = os.environ["DATABASE_URL"]
ADMIN_IDS: list[int] = [
    int(x) for x in os.environ.get("ADMIN_IDS", "").split(",") if x.strip().isdigit()
]

TH_TZ = ZoneInfo("Asia/Bangkok")
KEEP_ALIVE_PORT = int(os.environ.get("KEEP_ALIVE_PORT", "8099"))
ITEMS_PER_PAGE = 5

# Conversation states
CALC_AMOUNT, CALC_TYPE = range(2)
ADD_SCRIPT_TEXT = 10
ADD_CLIP_TITLE = 20
BROADCAST_TEXT = 30

# Commission rates
FEE_ACCOUNT = 0.35
FEE_SYSTEM = 0.05
COM_FAN = 0.30
COM_STAFF = 0.13

# ---------------------------------------------------------------------------
# Button labels
# ---------------------------------------------------------------------------
BTN_CHECKIN = "✅ เช็คอินสู้ตาย!"
BTN_CHECKOUT = "🔴 เลิกงานแล้วน้า"
BTN_BREAK = "☕ พักเติมพลัง"
BTN_RETURN = "🔙 กลับมาลุยต่อ"
BTN_CALC = "💰 คำนวณค่าคอมฯ"
BTN_SCRIPTS = "📖 คลังสคริปต์"
BTN_CLIPS = "📺 คลิปเตือนภัย จุ๊บๆ"
BTN_FAN = "👫 ลูกค้าของแฟน (30%)"
BTN_STAFF = "👔 ลูกค้าของพนักงาน (13%)"
BTN_CANCEL = "🙅‍♀️ ยกเลิกก่อนนะ"
BTN_MORE = "📋 เมนูเพิ่มเติม"

# Inline "more menu" callback data
CB_SCRIPTS = "menu_scripts"
CB_CLIPS = "menu_clips"
CB_SUMMARY = "menu_summary"
CB_PROFILE = "menu_profile"
CB_RANKING = "menu_ranking"
CB_EXPORT = "menu_export"
CB_WORKS = "menu_works"

# Work-entry parser: matches "name/amount" (e.g. "อันยอง/300000", "Bell / 5m")
WORK_ENTRY_RE = re.compile(r"([^\s/\\]+)\s*[/\\]\s*(\d[\d,\.]*m?)", re.IGNORECASE)

# ---------------------------------------------------------------------------
# Keyboards
# ---------------------------------------------------------------------------
# Compact daily keyboard: only the actions used every day stay on the
# ReplyKeyboard; everything else lives in the inline "more" menu so the
# keyboard does not feel crowded.
MAIN_KEYBOARD = ReplyKeyboardMarkup(
    [
        [BTN_CHECKIN, BTN_CHECKOUT],
        [BTN_BREAK, BTN_RETURN],
        [BTN_CALC, BTN_MORE],
    ],
    resize_keyboard=True,
)

# Inline "more" menu — attached to a message, keeps the keyboard clean.
MORE_MENU = InlineKeyboardMarkup(
    [
        [
            InlineKeyboardButton("📖 คลังสคริปต์", callback_data=CB_SCRIPTS),
            InlineKeyboardButton("📺 คลิปเตือนภัย", callback_data=CB_CLIPS),
        ],
        [
            InlineKeyboardButton("📊 สรุปวันนี้", callback_data=CB_SUMMARY),
            InlineKeyboardButton("📈 งานวันนี้", callback_data=CB_WORKS),
        ],
        [
            InlineKeyboardButton("👤 โปรไฟล์", callback_data=CB_PROFILE),
            InlineKeyboardButton("🏆 อันดับเดือนนี้", callback_data=CB_RANKING),
        ],
        [
            InlineKeyboardButton("📥 ส่งออก CSV", callback_data=CB_EXPORT),
        ],
    ]
)

TYPE_KEYBOARD = ReplyKeyboardMarkup(
    [
        [BTN_FAN, BTN_STAFF],
        [BTN_CANCEL],
    ],
    resize_keyboard=True,
)

# ---------------------------------------------------------------------------
# Reply pools
# ---------------------------------------------------------------------------
CHECKIN_REPLIES = [
    "อันยองมาแล้วววว🍑 วันนี้สู้ๆนะคะ เช็คอินให้แล้วจ้า จุ๊บม๊วฟ~ ✨",
    "อ้าวมาแล้วเหรอคะ เก่งมากเลย🍑 อันยองจดไว้ให้แล้วนะคะ วันนี้ต้องปังๆค่า!",
    "เข้างานแล้วค่ะ🍑 อันยองจดไว้ให้แล้วนะ สู้สู้! อันยองเชียร์อยู่นะคะ 🎀",
    "มาทำงานแล้วเหรอ เยี่ยมเลยค่ะ🍑 บันทึกเรียบร้อยแล้วจ้า ทำดีๆนะคะ วันนี้ต้องสว่างมากเลย~",
    "สวัสดีตอนเช้าค่ะ🍑 วันนี้พร้อมลุยเต็มที่เลยใช่มั้ยคะ? จดไว้ให้แล้ว ปังๆนะ! 💪",
]

CHECKOUT_REPLIES = [
    "เลิกงานแล้วเหรอคะ🍑 วันนี้เหนื่อยมั้ยคะ พักผ่อนเยอะๆนะ อันยองบันทึกไว้ให้แล้วจ้า 💖",
    "หมดวันแล้วววว🍑 อันยองจดให้เรียบร้อยค่า พรุ่งนี้เจอกันอีกนะคะ สู้ๆ!",
    "กลับบ้านได้แล้วค่ะ🍑 วันนี้ทำงานหนักมากเลย ขอบคุณที่ทุ่มเทนะคะ จุ๊บม๊วฟ~",
    "อันยองบันทึกเวลาเลิกงานไว้แล้วนะคะ🍑 คืนนี้นอนหลับพักผ่อนเยอะๆด้วยนะ ฝันดีค่า 🌙",
    "เก่งมากเลยค่ะวันนี้🍑 ไปพักผ่อนได้เลยจ้า อันยองจดเรียบร้อยแล้ว เจอกันพรุ่งนี้นะ! ✨",
]

BREAK_REPLIES = [
    "พักกลางวันแล้วค่ะ🍑 กินข้าวให้อร่อยนะคะ ชาร์จพลังให้เต็มเลย อันยองบันทึกไว้ให้แล้วจ้า~",
    "หิวข้าวเหรอคะ🍑 ไปกินได้เลยนะ อันยองบันทึกไว้ให้เรียบร้อยแล้วค่า ☕",
    "พักก่อนนะคะ🍑 อาหารอร่อยๆช่วยให้สมองปลอดโปร่งเลยค่า บันทึกแล้วจ้า กลับมาลุยต่อนะ!",
    "เวลาพักผ่อนมาถึงแล้วค่า🍑 กินข้าวอร่อยๆ แล้วกลับมาลุยกันต่อนะคะ จุ๊บ! 🍱",
]

RETURN_REPLIES = [
    "กลับมาแล้วเหรอคะ🍑 อิ่มข้าวแล้วก็มาลุยต่อเลย อันยองเชียร์อยู่นะ บันทึกแล้วจ้า 🔥",
    "ชาร์จพลังเสร็จแล้วก็มาสู้ต่อเลยค่ะ🍑 อันยองบันทึกไว้ให้แล้วนะ วันนี้ต้องปังมากๆ~",
    "กลับจากพักแล้วค่า🍑 พร้อมลุยแล้วใช่มั้ยคะ อันยองเชียร์อยู่ตลอดเลยนะ บันทึกแล้วจ้า ✨",
    "กลับมาเติมพลังเต็มที่แล้วใช่มั้ยคะ🍑 ไปกันต่อเลยจ้า อันยองบันทึกแล้ว! 💪",
]

DEFAULT_REPLIES = [
    "อันยองจดไว้ให้เรียบร้อยแล้วนะคะ🍑 มีอะไรให้ช่วยอีกบอกได้เลยนะคะ จุ๊บม๊วฟ~",
    "โอเคค่ะ🍑 บันทึกไว้ให้แล้วจ้า อันยองอยู่ตรงนี้เสมอนะคะ 💖",
    "รับทราบแล้วค่า🍑 จดเรียบร้อยเลย สู้ๆนะคะ วันนี้ต้องโกยๆๆ! 🔥",
    "โน้ตไว้ให้แล้วจ้า🍑 ถ้ามีอะไรอยากบอกอีกพิมพ์มาได้เลยนะคะ อันยองพร้อมเสมอ! 📝",
]

MANUAL = (
    "อันยองค่าาา! น้องอันยอง🍑 มาแล้วววว ✨\n\n"
    "วันนี้มีอะไรให้เค้าช่วยมั้ยคะ? กดปุ่มข้างล่างได้เลยนะ จุ๊บม๊วฟ! 🍑💖\n\n"
    "━━━━━━━━━━━━━━━━━━━━\n"
    "📖 *คู่มือการใช้งาน*\n\n"
    "✅ *เช็คอินสู้ตาย!*\n"
    "   → กดเมื่อมาถึงที่ทำงาน บันทึกเวลาเข้างาน\n\n"
    "🔴 *เลิกงานแล้วน้า*\n"
    "   → กดเมื่อเลิกงาน บันทึกเวลาออกงาน\n\n"
    "☕ *พักเติมพลัง*\n"
    "   → กดตอนออกไปพักกลางวัน\n\n"
    "🔙 *กลับมาลุยต่อ*\n"
    "   → กดตอนกลับจากพัก พร้อมทำงานต่อ\n\n"
    "💰 *คำนวณค่าคอมฯ*\n"
    "   → คำนวณค่าคอมมิชชั่น แยกตามประเภทลูกค้า\n\n"
    "📋 *เมนูเพิ่มเติม*\n"
    "   → รวมคลังสคริปต์ / คลิป / สรุป / โปรไฟล์ / อันดับ / ส่งออก CSV ไว้ในปุ่มเดียว\n\n"
    "━━━━━━━━━━━━━━━━━━━━\n"
    "📝 *บันทึกงานง่ายๆ*\n"
    "   → พิมพ์ *ชื่อ/ยอด* มาได้เลย (หลายบรรทัดก็ได้) เช่น\n"
    "      `อันยอง/300000`\n"
    "      `เบล/5m`\n"
    "   อันยองจะบันทึกให้ทุกรายการเลยค่ะ! (ส่งรูป+แคปชั่นก็อ่านได้)\n\n"
    "🔗 *ส่งลิงก์/คลิป*\n"
    "   → วางลิงก์มาได้เลย อันยองเก็บให้อัตโนมัติ\n\n"
    "━━━━━━━━━━━━━━━━━━━━\n"
    "📌 *คำสั่งพิเศษ*\n"
    "/summary  → สรุปชั่วโมงทำงานวันนี้\n"
    "/ranking  → ดูอันดับเช็คอินประจำเดือน\n"
    "/export   → ดาวน์โหลดข้อมูลเป็น CSV\n"
    "/works    → ดูงานที่บันทึกวันนี้\n"
    "/profile  → สถิติส่วนตัว\n"
    "/logs     → ประวัติล่าสุด 10 รายการ\n"
    "/clear    → ลบประวัติของตัวเอง\n"
    "/addscript → เพิ่มสคริปต์ (แอดมิน)\n"
    "/addclip   → เพิ่มคลิป (แอดมิน)\n"
    "/broadcast → ส่งข้อความถึงทุกคน (แอดมิน)\n"
    "/stats     → สถิติบอท (แอดมิน)\n"
    "/reminder  → เปิด/ปิดแจ้งเตือนเช็คเอาท์\n"
    "━━━━━━━━━━━━━━━━━━━━\n"
    "💡 หรือพิมพ์ข้อความอะไรก็ได้ อันยองจดให้เองเลยค่า\n"
    "สู้ๆนะคะทุกคน อันยองเชียร์อยู่นะ! 🍑"
)

# ---------------------------------------------------------------------------
# Keep-alive HTTP server
# ---------------------------------------------------------------------------


class KeepAliveHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write("Anyong is alive 🍑".encode())

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        pass


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def run_keep_alive() -> None:
    try:
        server = ReusableHTTPServer(("0.0.0.0", KEEP_ALIVE_PORT), KeepAliveHandler)
        logger.info("Keep-alive server on port %d", KEEP_ALIVE_PORT)
        server.serve_forever()
    except Exception:
        logger.exception("Keep-alive server crashed")


# ---------------------------------------------------------------------------
# Database layer (connection pool + retry)
# ---------------------------------------------------------------------------
_pool: psycopg2.pool.ThreadedConnectionPool | None = None


def get_pool() -> psycopg2.pool.ThreadedConnectionPool:
    global _pool
    if _pool is None or _pool.closed:
        _pool = psycopg2.pool.ThreadedConnectionPool(
            minconn=2,
            maxconn=10,
            dsn=DATABASE_URL,
            # Keep the DB session in Bangkok time so naive timestamps and
            # `::date` comparisons line up with now_th().
            options="-c timezone=Asia/Bangkok",
        )
        logger.info("Database connection pool created")
    return _pool


@contextmanager
def get_conn():
    """Yield a connection from the pool; return it when done."""
    pool = get_pool()
    conn = pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


def db_retry(func):
    """Retry a DB operation up to 3 times on connection errors."""

    @wraps(func)
    def wrapper(*args, **kwargs):
        last_exc: Exception | None = None
        for attempt in range(3):
            try:
                return func(*args, **kwargs)
            except psycopg2.OperationalError as exc:
                last_exc = exc
                logger.warning("DB retry %d/3: %s", attempt + 1, exc)
                time.sleep(0.5 * (attempt + 1))
                global _pool
                if _pool and not _pool.closed:
                    _pool.closeall()
                _pool = None
        raise last_exc  # type: ignore[misc]

    return wrapper


@db_retry
def init_db() -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS work_logs (
                    id         SERIAL PRIMARY KEY,
                    user_id    BIGINT NOT NULL,
                    user_name  TEXT   NOT NULL,
                    action     TEXT   NOT NULL,
                    logged_at  TIMESTAMP NOT NULL DEFAULT NOW()
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS scripts (
                    id       SERIAL PRIMARY KEY,
                    title    TEXT   NOT NULL,
                    body     TEXT   NOT NULL,
                    added_by BIGINT NOT NULL,
                    added_at TIMESTAMP NOT NULL DEFAULT NOW()
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS clips (
                    id       SERIAL PRIMARY KEY,
                    title    TEXT   NOT NULL,
                    url      TEXT   NOT NULL,
                    added_by BIGINT NOT NULL,
                    added_at TIMESTAMP NOT NULL DEFAULT NOW()
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS work_entries (
                    id          SERIAL PRIMARY KEY,
                    user_id     BIGINT NOT NULL,
                    user_name   TEXT   NOT NULL,
                    client_name TEXT   NOT NULL,
                    amount      TEXT   NOT NULL,
                    recorded_at TIMESTAMP NOT NULL DEFAULT NOW()
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS shared_links (
                    id          SERIAL PRIMARY KEY,
                    user_id     BIGINT NOT NULL,
                    user_name   TEXT   NOT NULL,
                    url         TEXT   NOT NULL,
                    recorded_at TIMESTAMP NOT NULL DEFAULT NOW()
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS user_settings (
                    user_id          BIGINT PRIMARY KEY,
                    user_name        TEXT   NOT NULL DEFAULT '',
                    reminder_enabled BOOLEAN NOT NULL DEFAULT FALSE,
                    created_at       TIMESTAMP NOT NULL DEFAULT NOW()
                )
            """)
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_work_logs_user_id
                ON work_logs (user_id)
            """)
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_work_logs_logged_at
                ON work_logs (logged_at)
            """)
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_work_entries_user_id
                ON work_entries (user_id)
            """)
    logger.info("Database initialised")


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------


def re_escape(s: str) -> str:
    """Escape regex special chars in button labels."""
    return re.escape(s)


def get_reply(replies: list[str], seed: int) -> str:
    return replies[seed % len(replies)]


def fmt(n: float) -> str:
    return f"{n:,.2f}"


def now_th() -> datetime:
    return datetime.now(TH_TZ)


def calc_commission(amount: float, rate: float) -> dict[str, float]:
    fee_acc = amount * FEE_ACCOUNT
    after_acc = amount - fee_acc
    fee_sys = after_acc * FEE_SYSTEM
    after_sys = after_acc - fee_sys
    commission = after_sys * rate
    return {
        "amount": amount,
        "rate": rate,
        "fee_acc": fee_acc,
        "after_acc": after_acc,
        "fee_sys": fee_sys,
        "after_sys": after_sys,
        "commission": commission,
    }


def is_admin(user_id: int) -> bool:
    return user_id in ADMIN_IDS


# ---------------------------------------------------------------------------
# /start, /anyong
# ---------------------------------------------------------------------------


async def anyong(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    await update.message.reply_text(
        MANUAL,
        reply_markup=MAIN_KEYBOARD,
        parse_mode=ParseMode.MARKDOWN,
    )


# ---------------------------------------------------------------------------
# Commission conversation
# ---------------------------------------------------------------------------


async def calc_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message:
        return ConversationHandler.END
    await update.message.reply_text(
        "💰 อันยองช่วยคิดค่าคอมให้นะคะ🍑\n\n"
        "พิมพ์ยอดเงิน (ตัวเลขเท่านั้นนะคะ) เลยค่า เช่น  300000",
        reply_markup=ReplyKeyboardRemove(),
    )
    return CALC_AMOUNT


async def calc_get_amount(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message:
        return ConversationHandler.END
    raw = update.message.text.strip().replace(",", "").replace(" ", "") if update.message.text else ""
    try:
        amount = float(raw)
        if amount <= 0:
            raise ValueError
    except ValueError:
        await update.message.reply_text(
            "🍑 อ๊ะ~ ใส่ตัวเลขด้วยนะคะ เช่น 300000 แล้วลองใหม่ได้เลยค่า"
        )
        return CALC_AMOUNT

    if context.user_data is not None:
        context.user_data["calc_amount"] = amount
    await update.message.reply_text(
        f"ยอดเงิน {fmt(amount)} บาท รับทราบแล้วค่ะ🍑\n\n"
        "ลูกค้าคนนี้เป็นลูกค้าของใครคะ~?",
        reply_markup=TYPE_KEYBOARD,
    )
    return CALC_TYPE


async def calc_get_type(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message:
        return ConversationHandler.END
    text = (update.message.text or "").strip()

    if text == BTN_CANCEL:
        await update.message.reply_text(
            "โอเคค่ะ🍑 ยกเลิกแล้วนะคะ กลับมาคิดใหม่ได้ตลอดเลยนะ~",
            reply_markup=MAIN_KEYBOARD,
        )
        return ConversationHandler.END

    if "แฟน" in text:
        rate = COM_FAN
        label = "ลูกค้าของแฟน"
    elif "พนักงาน" in text:
        rate = COM_STAFF
        label = "ลูกค้าของพนักงาน"
    else:
        await update.message.reply_text("🍑 กรุณาเลือกจากปุ่มด้านล่างเลยนะคะ~")
        return CALC_TYPE

    amount = context.user_data.get("calc_amount", 0) if context.user_data else 0
    c = calc_commission(amount, rate)

    result = (
        f"🍑 สรุปค่าคอมนะคะ~\n"
        f"{'─' * 30}\n"
        f"📌 ประเภท         : {label}\n"
        f"💵 ยอดเงินเต็ม    : {fmt(c['amount'])} บาท\n"
        f"{'─' * 30}\n"
        f"➖ ค่าบัญชี (35%) : {fmt(c['fee_acc'])} บาท\n"
        f"   เหลือ           : {fmt(c['after_acc'])} บาท\n"
        f"➖ ค่าระบบ  (5%)  : {fmt(c['fee_sys'])} บาท\n"
        f"   เหลือ           : {fmt(c['after_sys'])} บาท\n"
        f"{'─' * 30}\n"
        f"✅ ค่าคอม ({int(rate * 100)}%)    : {fmt(c['commission'])} บาท 🎉\n\n"
        f"สู้ๆนะคะ อันยองเชียร์อยู่! 🍑🔥"
    )
    await update.message.reply_text(result, reply_markup=MAIN_KEYBOARD)
    return ConversationHandler.END


async def calc_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if update.message:
        await update.message.reply_text(
            "ยกเลิกแล้วค่ะ🍑 กลับเมนูหลักแล้วนะ~",
            reply_markup=MAIN_KEYBOARD,
        )
    return ConversationHandler.END


# ---------------------------------------------------------------------------
# Scripts (paginated inline buttons)
# ---------------------------------------------------------------------------


@db_retry
def _fetch_scripts(page: int = 0) -> tuple[list[tuple[int, str]], int]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM scripts")
            total = cur.fetchone()[0]
            cur.execute(
                "SELECT id, title FROM scripts ORDER BY added_at DESC LIMIT %s OFFSET %s",
                (ITEMS_PER_PAGE, page * ITEMS_PER_PAGE),
            )
            rows = cur.fetchall()
    return rows, total


def _scripts_keyboard(rows: list[tuple[int, str]], page: int, total: int) -> InlineKeyboardMarkup:
    keyboard = [
        [InlineKeyboardButton(f"📄 {row[1]}", callback_data=f"script_{row[0]}")]
        for row in rows
    ]
    nav_row: list[InlineKeyboardButton] = []
    if page > 0:
        nav_row.append(InlineKeyboardButton("⬅️ ก่อนหน้า", callback_data=f"scripts_page_{page - 1}"))
    total_pages = max(1, (total + ITEMS_PER_PAGE - 1) // ITEMS_PER_PAGE)
    if page < total_pages - 1:
        nav_row.append(InlineKeyboardButton("➡️ ถัดไป", callback_data=f"scripts_page_{page + 1}"))
    if nav_row:
        keyboard.append(nav_row)
    return InlineKeyboardMarkup(keyboard)


async def _send_scripts(msg) -> None:
    rows, total = _fetch_scripts(0)
    if not rows:
        await msg.reply_text(
            "📖 ยังไม่มีสคริปต์ในคลังเลยค่ะ🍑\n\n"
            "แอดมินสามารถเพิ่มสคริปต์ได้ด้วยคำสั่ง /addscript นะคะ 💖",
            reply_markup=MAIN_KEYBOARD,
        )
        return
    await msg.reply_text(
        f"📖 คลังสคริปต์สุดปัง ({total} รายการ) เลือกที่ชอบแล้วไปปิดการขายเลยค่ะ! 🍑🔥",
        reply_markup=_scripts_keyboard(rows, 0, total),
    )


async def menu_scripts(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    await _send_scripts(update.message)


async def scripts_page_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query:
        return
    await query.answer()
    page = int(query.data.split("_")[-1])
    rows, total = _fetch_scripts(page)
    await query.edit_message_text(
        f"📖 คลังสคริปต์สุดปัง ({total} รายการ) หน้า {page + 1} 🍑🔥",
        reply_markup=_scripts_keyboard(rows, page, total),
    )


@db_retry
def _fetch_script_body(script_id: int) -> tuple[str, str] | None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT title, body FROM scripts WHERE id = %s", (script_id,))
            return cur.fetchone()


async def script_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query:
        return
    await query.answer()
    script_id = int(query.data.split("_")[1])
    row = _fetch_script_body(script_id)
    if not row:
        await query.message.reply_text("🍑 ขอโทษนะคะ ไม่พบสคริปต์นี้แล้วค่า")
        return
    title, body = row
    await query.message.reply_text(
        f"📄 *{title}*\n\n{body}\n\n"
        "━━━━━━━━━━━━━━━━━━━━\n"
        "ไปปิดการขายให้ยอดพุ่งนะคะ อันยองเชียร์อยู่! 🍑🔥",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=MAIN_KEYBOARD,
    )


async def add_script_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message:
        return ConversationHandler.END
    await update.message.reply_text(
        "📖 เพิ่มสคริปต์ใหม่เลยค่า🍑\n\n"
        "พิมพ์ *หัวข้อ | เนื้อหา* มาได้เลยนะคะ\n"
        "ตัวอย่าง: เปิดบทสนทนา | สวัสดีค่ะ ขอแนะนำโปรฯ ดีๆ...\n\n"
        "หรือพิมพ์ /cancel เพื่อยกเลิกนะคะ",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=ReplyKeyboardRemove(),
    )
    return ADD_SCRIPT_TEXT


@db_retry
def _insert_script(title: str, body: str, user_id: int) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO scripts (title, body, added_by) VALUES (%s, %s, %s)",
                (title, body, user_id),
            )


async def add_script_save(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message:
        return ConversationHandler.END
    text = (update.message.text or "").strip()
    if "|" not in text:
        await update.message.reply_text(
            "🍑 ขอรูปแบบ *หัวข้อ | เนื้อหา* ด้วยนะคะ แล้วลองใหม่ได้เลย~",
            parse_mode=ParseMode.MARKDOWN,
        )
        return ADD_SCRIPT_TEXT

    parts = text.split("|", 1)
    title = parts[0].strip()
    body = parts[1].strip()
    _insert_script(title, body, update.message.from_user.id)

    await update.message.reply_text(
        f"✅ เพิ่มสคริปต์ *{title}* เรียบร้อยแล้วค่า🍑 ปังมากเลยนะ! 🔥",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=MAIN_KEYBOARD,
    )
    return ConversationHandler.END


@db_retry
def _delete_script(script_id: int) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM scripts WHERE id = %s", (script_id,))


async def del_script(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    args = context.args
    if not args or not args[0].isdigit():
        await update.message.reply_text(
            "🍑 ใช้คำสั่ง /delscript [id] นะคะ เช่น /delscript 1",
            reply_markup=MAIN_KEYBOARD,
        )
        return
    script_id = int(args[0])
    _delete_script(script_id)
    await update.message.reply_text(
        f"🗑️ ลบสคริปต์ #{script_id} เรียบร้อยแล้วค่า🍑",
        reply_markup=MAIN_KEYBOARD,
    )


# ---------------------------------------------------------------------------
# Clips (paginated)
# ---------------------------------------------------------------------------


@db_retry
def _fetch_clips(page: int = 0) -> tuple[list[tuple[int, str, str]], int]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM clips")
            total = cur.fetchone()[0]
            cur.execute(
                "SELECT id, title, url FROM clips ORDER BY added_at DESC LIMIT %s OFFSET %s",
                (ITEMS_PER_PAGE, page * ITEMS_PER_PAGE),
            )
            rows = cur.fetchall()
    return rows, total


def _clips_keyboard(rows: list[tuple[int, str, str]], page: int, total: int) -> InlineKeyboardMarkup:
    keyboard = [
        [InlineKeyboardButton(f"🎬 {row[1]}", url=row[2])]
        for row in rows
    ]
    nav_row: list[InlineKeyboardButton] = []
    if page > 0:
        nav_row.append(InlineKeyboardButton("⬅️ ก่อนหน้า", callback_data=f"clips_page_{page - 1}"))
    total_pages = max(1, (total + ITEMS_PER_PAGE - 1) // ITEMS_PER_PAGE)
    if page < total_pages - 1:
        nav_row.append(InlineKeyboardButton("➡️ ถัดไป", callback_data=f"clips_page_{page + 1}"))
    if nav_row:
        keyboard.append(nav_row)
    return InlineKeyboardMarkup(keyboard)


async def _send_clips(msg) -> None:
    rows, total = _fetch_clips(0)
    if not rows:
        await msg.reply_text(
            "📺 ยังไม่มีคลิปเตือนภัยในคลังเลยค่ะ🍑\n\n"
            "แอดมินสามารถเพิ่มได้ด้วยคำสั่ง /addclip นะคะ 💖",
            reply_markup=MAIN_KEYBOARD,
        )
        return
    await msg.reply_text(
        f"📺 คลิปเตือนภัยมิจฉาชีพ ({total} คลิป) ดูแล้วระวังตัวด้วยนะคะ 🍑💕",
        reply_markup=_clips_keyboard(rows, 0, total),
    )


async def menu_clips(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    await _send_clips(update.message)


async def clips_page_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query:
        return
    await query.answer()
    page = int(query.data.split("_")[-1])
    rows, total = _fetch_clips(page)
    total_pages = max(1, (total + ITEMS_PER_PAGE - 1) // ITEMS_PER_PAGE)
    await query.edit_message_text(
        f"📺 คลิปเตือนภัย หน้า {page + 1}/{total_pages} 🍑💕",
        reply_markup=_clips_keyboard(rows, page, total),
    )


async def add_clip_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message:
        return ConversationHandler.END
    await update.message.reply_text(
        "📺 เพิ่มคลิปเตือนภัยใหม่เลยค่า🍑\n\n"
        "พิมพ์ *ชื่อคลิป | ลิงก์* มาได้เลยนะคะ\n"
        "ตัวอย่าง: สแกมเมอร์หลอกโอน | https://youtu.be/xxx\n\n"
        "หรือพิมพ์ /cancel เพื่อยกเลิกนะคะ",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=ReplyKeyboardRemove(),
    )
    return ADD_CLIP_TITLE


@db_retry
def _insert_clip(title: str, url: str, user_id: int) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO clips (title, url, added_by) VALUES (%s, %s, %s)",
                (title, url, user_id),
            )


async def add_clip_save(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message:
        return ConversationHandler.END
    text = (update.message.text or "").strip()
    if "|" not in text:
        await update.message.reply_text(
            "🍑 ขอรูปแบบ *ชื่อคลิป | ลิงก์* ด้วยนะคะ แล้วลองใหม่ได้เลย~",
            parse_mode=ParseMode.MARKDOWN,
        )
        return ADD_CLIP_TITLE

    parts = text.split("|", 1)
    title = parts[0].strip()
    url = parts[1].strip()
    _insert_clip(title, url, update.message.from_user.id)

    await update.message.reply_text(
        f"✅ เพิ่มคลิป *{title}* เรียบร้อยแล้วค่า🍑 ขอบคุณที่แชร์นะคะ 💖",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=MAIN_KEYBOARD,
    )
    return ConversationHandler.END


@db_retry
def _delete_clip(clip_id: int) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM clips WHERE id = %s", (clip_id,))


async def del_clip(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    args = context.args
    if not args or not args[0].isdigit():
        await update.message.reply_text(
            "🍑 ใช้คำสั่ง /delclip [id] นะคะ เช่น /delclip 1",
            reply_markup=MAIN_KEYBOARD,
        )
        return
    clip_id = int(args[0])
    _delete_clip(clip_id)
    await update.message.reply_text(
        f"🗑️ ลบคลิป #{clip_id} เรียบร้อยแล้วค่า🍑",
        reply_markup=MAIN_KEYBOARD,
    )


async def add_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if update.message:
        await update.message.reply_text(
            "ยกเลิกแล้วค่ะ🍑 กลับเมนูหลักแล้วนะ~",
            reply_markup=MAIN_KEYBOARD,
        )
    return ConversationHandler.END


# ---------------------------------------------------------------------------
# Work log handlers
# ---------------------------------------------------------------------------


@db_retry
def _insert_log(user_id: int, user_name: str, action: str, logged_at: datetime) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO work_logs (user_id, user_name, action, logged_at) VALUES (%s, %s, %s, %s)",
                (user_id, user_name, action, logged_at),
            )


@db_retry
def _upsert_user(user_id: int, user_name: str) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO user_settings (user_id, user_name)
                   VALUES (%s, %s)
                   ON CONFLICT (user_id) DO UPDATE SET user_name = EXCLUDED.user_name""",
                (user_id, user_name),
            )


@db_retry
def _insert_work_entries(
    user_id: int, user_name: str, entries: list[tuple[str, str]], recorded_at: datetime
) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.executemany(
                """INSERT INTO work_entries
                       (user_id, user_name, client_name, amount, recorded_at)
                   VALUES (%s, %s, %s, %s, %s)""",
                [(user_id, user_name, name, amount, recorded_at) for name, amount in entries],
            )


@db_retry
def _insert_links(
    user_id: int, user_name: str, urls: list[str], recorded_at: datetime
) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.executemany(
                """INSERT INTO shared_links (user_id, user_name, url, recorded_at)
                   VALUES (%s, %s, %s, %s)""",
                [(user_id, user_name, url, recorded_at) for url in urls],
            )


def _parse_work_entries(text: str) -> list[tuple[str, str]]:
    """Parse 'name/amount' lines into (name, amount) tuples."""
    entries: list[tuple[str, str]] = []
    for line in text.splitlines():
        match = WORK_ENTRY_RE.search(line)
        if match:
            name = match.group(1).strip(" .,:-")
            amount = match.group(2).strip()
            if name:
                entries.append((name, amount))
    return entries


def _extract_urls(message) -> list[str]:
    """Pull URLs out of a message via entities, with a regex fallback."""
    body = message.text or message.caption or ""
    entities = message.entities or message.caption_entities or []
    urls: list[str] = []
    for ent in entities:
        if ent.type == MessageEntity.URL:
            urls.append(body[ent.offset : ent.offset + ent.length])
        elif ent.type == MessageEntity.TEXT_LINK and ent.url:
            urls.append(ent.url)
    if not urls:
        urls = re.findall(r"https?://\S+", body)
    # de-duplicate while preserving order
    seen: set[str] = set()
    return [u for u in urls if not (u in seen or seen.add(u))]


# Replies for daily-action buttons (logged to work_logs for stats/ranking).
_ACTION_REPLIES = {
    BTN_CHECKIN: lambda: CHECKIN_REPLIES,
    BTN_BREAK: lambda: BREAK_REPLIES,
    BTN_RETURN: lambda: RETURN_REPLIES,
}


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.from_user:
        return
    msg = update.message
    user = msg.from_user
    text = (msg.text or msg.caption or "").strip()
    now = now_th()
    timestamp = now.strftime("%Y-%m-%d %H:%M:%S")
    seed = user.id + int(now.timestamp())

    # 1) Daily-action buttons → log + reply (these feed summary/ranking).
    if text in (BTN_CHECKIN, BTN_CHECKOUT, BTN_BREAK, BTN_RETURN):
        _insert_log(user.id, user.full_name, text, now)
        _upsert_user(user.id, user.full_name)
        if text == BTN_CHECKOUT:
            reply = get_reply(CHECKOUT_REPLIES, seed)
            hours = _calc_today_hours(user.id)
            if hours is not None:
                reply += f"\n\n⏱️ วันนี้ทำงานรวม {hours:.1f} ชั่วโมงค่ะ"
        else:
            reply = get_reply(_ACTION_REPLIES[text](), seed)
        await msg.reply_text(
            f"{reply}\n\n👤 {user.full_name}  🕐 {timestamp}",
            reply_markup=MAIN_KEYBOARD,
        )
        return

    # 2) "More" menu → show the inline menu (keeps the keyboard tidy).
    if text == BTN_MORE:
        await msg.reply_text(
            "📋 เมนูเพิ่มเติมค่ะ🍑 เลือกที่อยากดูได้เลยน้า~",
            reply_markup=MORE_MENU,
        )
        return

    # 3) Links / clips → save automatically (check before work entries since
    #    URLs also contain '/').
    urls = _extract_urls(msg)
    if urls:
        _upsert_user(user.id, user.full_name)
        _insert_links(user.id, user.full_name, urls, now)
        await msg.reply_text(
            f"📺 รับทราบค่ะ! อันยองเก็บลิงก์ให้แล้ว {len(urls)} รายการ จุ๊บๆ 🍑",
            reply_markup=MAIN_KEYBOARD,
        )
        return

    # 4) Work entries "ชื่อ/ยอด" (single or multi-line).
    if "/" in text or "\\" in text:
        entries = _parse_work_entries(text)
        if entries:
            _upsert_user(user.id, user.full_name)
            _insert_work_entries(user.id, user.full_name, entries, now)
            preview = "\n".join(f"  • {n}  /  {a}" for n, a in entries[:10])
            extra = (
                f"\n…และอีก {len(entries) - 10} รายการ" if len(entries) > 10 else ""
            )
            await msg.reply_text(
                f"🍑 อันยองบันทึกงานให้แล้ว {len(entries)} รายการ "
                f"เก่งมากเลยค่ะ คนดี~ จุ๊บม๊วฟ!\n\n{preview}{extra}",
                reply_markup=MAIN_KEYBOARD,
            )
            return

    # 5) Anything else → friendly reply only (no DB write, keeps things light).
    await msg.reply_text(
        f"{get_reply(DEFAULT_REPLIES, seed)}\n\n👤 {user.full_name}  🕐 {timestamp}",
        reply_markup=MAIN_KEYBOARD,
    )


# ---------------------------------------------------------------------------
# /summary - daily work summary
# ---------------------------------------------------------------------------


@db_retry
def _get_today_logs(user_id: int) -> list[tuple[str, datetime]]:
    today = now_th().date()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT action, logged_at FROM work_logs
                   WHERE user_id = %s AND logged_at::date = %s
                   ORDER BY logged_at ASC""",
                (user_id, today),
            )
            return cur.fetchall()


def _calc_today_hours(user_id: int) -> float | None:
    logs = _get_today_logs(user_id)
    if not logs:
        return None
    checkin_time: datetime | None = None
    break_time: datetime | None = None
    total_seconds = 0.0
    for action, ts in logs:
        if BTN_CHECKIN in action:
            checkin_time = ts
        elif BTN_BREAK in action:
            if checkin_time:
                total_seconds += (ts - checkin_time).total_seconds()
                checkin_time = None
            break_time = ts
        elif BTN_RETURN in action:
            if break_time:
                checkin_time = ts
                break_time = None
        elif BTN_CHECKOUT in action:
            if checkin_time:
                total_seconds += (ts - checkin_time).total_seconds()
                checkin_time = None
    if checkin_time:
        total_seconds += (now_th().replace(tzinfo=None) - checkin_time).total_seconds()
    return total_seconds / 3600 if total_seconds > 0 else None


@db_retry
def _get_today_entries(user_id: int) -> list[tuple[str, str, datetime]]:
    today = now_th().date()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT client_name, amount, recorded_at FROM work_entries
                   WHERE user_id = %s AND recorded_at::date = %s
                   ORDER BY recorded_at ASC""",
                (user_id, today),
            )
            return cur.fetchall()


async def _send_summary(msg, user_id: int) -> None:
    logs = _get_today_logs(user_id)
    entries = _get_today_entries(user_id)
    if not logs and not entries:
        await msg.reply_text(
            "📊 วันนี้ยังไม่มีข้อมูลเลยค่ะ🍑 ลองเช็คอินก่อนนะคะ~",
            reply_markup=MAIN_KEYBOARD,
        )
        return

    lines = ["📊 *สรุปวันนี้* 🍑\n"]
    for action, ts in logs:
        t = ts.strftime("%H:%M:%S")
        lines.append(f"  🕐 {t}  →  {action}")

    hours = _calc_today_hours(user_id)
    if hours is not None:
        lines.append(f"\n⏱️ ชั่วโมงทำงานรวม: *{hours:.1f} ชม.*")
    if entries:
        lines.append(f"📝 งานที่บันทึกวันนี้: *{len(entries)} รายการ*")
    lines.append("\nสู้ๆนะคะ อันยองเชียร์อยู่! 🍑🔥")

    await msg.reply_text(
        "\n".join(lines),
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=MAIN_KEYBOARD,
    )


async def _send_works(msg, user_id: int) -> None:
    entries = _get_today_entries(user_id)
    if not entries:
        await msg.reply_text(
            "📈 วันนี้ยังไม่มีงานที่บันทึกเลยค่ะ🍑\n"
            "พิมพ์ *ชื่อ/ยอด* มาได้เลยน้า~",
            parse_mode=ParseMode.MARKDOWN,
            reply_markup=MAIN_KEYBOARD,
        )
        return
    lines = [f"📈 *งานวันนี้* ({len(entries)} รายการ) 🍑\n"]
    for client, amount, ts in entries:
        t = ts.strftime("%H:%M")
        lines.append(f"  🕐 {t}  •  {client}  /  {amount}")
    lines.append("\nเก่งมากเลยค่ะ! อันยองภูมิใจ 🍑💖")
    await msg.reply_text(
        "\n".join(lines),
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=MAIN_KEYBOARD,
    )


async def summary_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.from_user:
        return
    await _send_summary(update.message, update.message.from_user.id)


async def works_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.from_user:
        return
    await _send_works(update.message, update.message.from_user.id)


# ---------------------------------------------------------------------------
# /profile - personal stats
# ---------------------------------------------------------------------------


@db_retry
def _get_profile_stats(user_id: int) -> dict[str, Any]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM work_logs WHERE user_id = %s",
                (user_id,),
            )
            total_logs = cur.fetchone()[0]

            cur.execute(
                """SELECT COUNT(*) FROM work_logs
                   WHERE user_id = %s AND action LIKE %s""",
                (user_id, f"%{BTN_CHECKIN}%"),
            )
            total_checkins = cur.fetchone()[0]

            cur.execute(
                """SELECT MIN(logged_at), MAX(logged_at) FROM work_logs
                   WHERE user_id = %s""",
                (user_id,),
            )
            first_log, last_log = cur.fetchone()

            cur.execute(
                """SELECT COUNT(DISTINCT logged_at::date) FROM work_logs
                   WHERE user_id = %s AND action LIKE %s""",
                (user_id, f"%{BTN_CHECKIN}%"),
            )
            days_worked = cur.fetchone()[0]

    return {
        "total_logs": total_logs,
        "total_checkins": total_checkins,
        "first_log": first_log,
        "last_log": last_log,
        "days_worked": days_worked,
    }


async def _send_profile(msg, user_id: int, full_name: str) -> None:
    stats = _get_profile_stats(user_id)
    first = stats["first_log"].strftime("%Y-%m-%d") if stats["first_log"] else "ยังไม่มี"
    last = stats["last_log"].strftime("%Y-%m-%d") if stats["last_log"] else "ยังไม่มี"

    hours = _calc_today_hours(user_id)
    hours_text = f"{hours:.1f} ชม." if hours else "ยังไม่เช็คอิน"

    body = (
        f"👤 *โปรไฟล์ของ {full_name}* 🍑\n"
        f"{'━' * 28}\n"
        f"📅 วันที่เริ่มใช้งาน : {first}\n"
        f"📅 ใช้งานล่าสุด    : {last}\n"
        f"✅ เช็คอินทั้งหมด  : {stats['total_checkins']} ครั้ง\n"
        f"📝 กิจกรรมทั้งหมด : {stats['total_logs']} รายการ\n"
        f"📆 จำนวนวันทำงาน : {stats['days_worked']} วัน\n"
        f"⏱️ วันนี้           : {hours_text}\n"
        f"{'━' * 28}\n"
        f"สู้ๆนะคะ อันยองภูมิใจในตัวคุณ! 🍑💖"
    )
    await msg.reply_text(
        body, parse_mode=ParseMode.MARKDOWN, reply_markup=MAIN_KEYBOARD
    )


async def profile_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.from_user:
        return
    await _send_profile(
        update.message, update.message.from_user.id, update.message.from_user.full_name
    )


# ---------------------------------------------------------------------------
# /ranking - monthly leaderboard
# ---------------------------------------------------------------------------


@db_retry
def _get_ranking() -> list[tuple[str, int]]:
    first_of_month = now_th().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT user_name, COUNT(*) AS cnt
                   FROM work_logs
                   WHERE action LIKE %s AND logged_at >= %s
                   GROUP BY user_name
                   ORDER BY cnt DESC
                   LIMIT 10""",
                (f"%{BTN_CHECKIN}%", first_of_month),
            )
            return cur.fetchall()


async def _send_ranking(msg) -> None:
    rows = _get_ranking()
    if not rows:
        await msg.reply_text(
            "🏆 ยังไม่มีข้อมูลเลยค่ะ🍑 ลองเช็คอินก่อนนะคะ~",
            reply_markup=MAIN_KEYBOARD,
        )
        return

    medals = ["🥇", "🥈", "🥉"]
    month_name = now_th().strftime("%B %Y")
    lines = [f"🏆 *อันดับเช็คอินประจำเดือน* 🍑\n📅 {month_name}\n"]
    for i, (name, cnt) in enumerate(rows):
        medal = medals[i] if i < 3 else f"  {i + 1}."
        lines.append(f"{medal} {name}  →  {cnt} ครั้ง")
    lines.append("\nสู้ๆนะคะ ใครจะคว้าอันดับ 1! 🍑🔥")

    await msg.reply_text(
        "\n".join(lines),
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=MAIN_KEYBOARD,
    )


async def ranking_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    await _send_ranking(update.message)


# ---------------------------------------------------------------------------
# /export - CSV download
# ---------------------------------------------------------------------------


@db_retry
def _export_logs(user_id: int) -> list[tuple]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT logged_at, action FROM work_logs
                   WHERE user_id = %s ORDER BY logged_at ASC""",
                (user_id,),
            )
            return cur.fetchall()


async def _send_export(msg, user_id: int) -> None:
    rows = _export_logs(user_id)
    if not rows:
        await msg.reply_text(
            "📤 ยังไม่มีข้อมูลให้ดาวน์โหลดค่ะ🍑",
            reply_markup=MAIN_KEYBOARD,
        )
        return

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["timestamp", "action"])
    for logged_at, action in rows:
        writer.writerow([logged_at.strftime("%Y-%m-%d %H:%M:%S"), action])

    buf.seek(0)
    bio = io.BytesIO(buf.getvalue().encode("utf-8-sig"))
    bio.name = f"work_logs_{user_id}.csv"

    await msg.reply_document(
        document=bio,
        filename=bio.name,
        caption="📤 ไฟล์ CSV สำหรับคุณค่ะ🍑 เปิดใน Excel ได้เลยนะ~",
        reply_markup=MAIN_KEYBOARD,
    )


async def export_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.from_user:
        return
    await _send_export(update.message, update.message.from_user.id)


# ---------------------------------------------------------------------------
# /logs - recent logs
# ---------------------------------------------------------------------------


@db_retry
def _recent_logs() -> list[tuple]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT logged_at, user_name, action FROM work_logs ORDER BY logged_at DESC LIMIT 10"
            )
            return cur.fetchall()


async def list_logs(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message:
        return
    rows = _recent_logs()
    if not rows:
        await update.message.reply_text(
            "ยังไม่มีข้อมูลเลยค่ะ🍑 ลองกด เช็คอินสู้ตาย! ก่อนเลยนะคะ~",
            reply_markup=MAIN_KEYBOARD,
        )
        return
    lines = ["🗒️ ประวัติล่าสุดนะคะ🍑\n"]
    for logged_at, user_name, action in reversed(rows):
        ts = logged_at.strftime("%Y-%m-%d %H:%M:%S")
        lines.append(f"[{ts}] {user_name}: {action}")
    await update.message.reply_text("\n".join(lines), reply_markup=MAIN_KEYBOARD)


# ---------------------------------------------------------------------------
# /clear - personal log clear
# ---------------------------------------------------------------------------


@db_retry
def _clear_user_logs(user_id: int) -> None:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM work_logs WHERE user_id = %s", (user_id,))


async def clear_logs(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.from_user:
        return
    _clear_user_logs(update.message.from_user.id)
    await update.message.reply_text(
        "โอเคค่ะ🍑 อันยองลบข้อมูลของคุณออกหมดแล้วนะคะ เริ่มใหม่ได้เลยจ้า~",
        reply_markup=MAIN_KEYBOARD,
    )


# ---------------------------------------------------------------------------
# /reminder - toggle checkout reminder
# ---------------------------------------------------------------------------


@db_retry
def _toggle_reminder(user_id: int) -> bool:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO user_settings (user_id, reminder_enabled)
                   VALUES (%s, TRUE)
                   ON CONFLICT (user_id) DO UPDATE
                   SET reminder_enabled = NOT user_settings.reminder_enabled
                   RETURNING reminder_enabled""",
                (user_id,),
            )
            return cur.fetchone()[0]


async def reminder_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.from_user:
        return
    enabled = _toggle_reminder(update.message.from_user.id)
    status = "เปิด ✅" if enabled else "ปิด ❌"
    await update.message.reply_text(
        f"🔔 แจ้งเตือนเช็คเอาท์: *{status}*\n\n"
        "อันยองจะเตือนตอน 18:00 ถ้าลืมเช็คเอาท์นะคะ🍑",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=MAIN_KEYBOARD,
    )


# ---------------------------------------------------------------------------
# /broadcast (admin only)
# ---------------------------------------------------------------------------


async def broadcast_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message or not update.message.from_user:
        return ConversationHandler.END
    if not is_admin(update.message.from_user.id):
        await update.message.reply_text(
            "🍑 ขอโทษค่ะ คำสั่งนี้สำหรับแอดมินเท่านั้นนะคะ~",
            reply_markup=MAIN_KEYBOARD,
        )
        return ConversationHandler.END

    await update.message.reply_text(
        "📢 พิมพ์ข้อความที่ต้องการประกาศเลยค่ะ🍑\n"
        "หรือพิมพ์ /cancel เพื่อยกเลิก",
        reply_markup=ReplyKeyboardRemove(),
    )
    return BROADCAST_TEXT


@db_retry
def _get_all_user_ids() -> list[int]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT DISTINCT user_id FROM user_settings")
            return [row[0] for row in cur.fetchall()]


async def broadcast_send(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    if not update.message:
        return ConversationHandler.END
    text = (update.message.text or "").strip()
    user_ids = _get_all_user_ids()

    success = 0
    failed = 0
    for uid in user_ids:
        try:
            await context.bot.send_message(
                chat_id=uid,
                text=f"📢 *ประกาศจากแอดมิน* 🍑\n\n{text}",
                parse_mode=ParseMode.MARKDOWN,
            )
            success += 1
        except Exception:
            failed += 1

    await update.message.reply_text(
        f"📢 ส่งประกาศเรียบร้อยแล้วค่า🍑\n"
        f"✅ สำเร็จ: {success} คน\n"
        f"❌ ล้มเหลว: {failed} คน",
        reply_markup=MAIN_KEYBOARD,
    )
    return ConversationHandler.END


# ---------------------------------------------------------------------------
# /stats (admin only)
# ---------------------------------------------------------------------------


@db_retry
def _get_bot_stats() -> dict[str, Any]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(DISTINCT user_id) FROM work_logs")
            total_users = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM work_logs")
            total_logs = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM scripts")
            total_scripts = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM clips")
            total_clips = cur.fetchone()[0]

            today = now_th().date()
            cur.execute(
                "SELECT COUNT(DISTINCT user_id) FROM work_logs WHERE logged_at::date = %s",
                (today,),
            )
            today_users = cur.fetchone()[0]
    return {
        "total_users": total_users,
        "total_logs": total_logs,
        "total_scripts": total_scripts,
        "total_clips": total_clips,
        "today_users": today_users,
    }


async def stats_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not update.message or not update.message.from_user:
        return
    if not is_admin(update.message.from_user.id):
        await update.message.reply_text(
            "🍑 ขอโทษค่ะ คำสั่งนี้สำหรับแอดมินเท่านั้นนะคะ~",
            reply_markup=MAIN_KEYBOARD,
        )
        return

    s = _get_bot_stats()
    msg = (
        f"📊 *สถิติบอท* 🍑\n"
        f"{'━' * 28}\n"
        f"👥 ผู้ใช้ทั้งหมด     : {s['total_users']} คน\n"
        f"👥 ผู้ใช้วันนี้      : {s['today_users']} คน\n"
        f"📝 กิจกรรมทั้งหมด  : {s['total_logs']} รายการ\n"
        f"📖 สคริปต์          : {s['total_scripts']} รายการ\n"
        f"📺 คลิป            : {s['total_clips']} รายการ\n"
        f"{'━' * 28}\n"
    )
    await update.message.reply_text(
        msg, parse_mode=ParseMode.MARKDOWN, reply_markup=MAIN_KEYBOARD
    )


# ---------------------------------------------------------------------------
# Checkout reminder job
# ---------------------------------------------------------------------------


@db_retry
def _get_unchecked_out_users() -> list[int]:
    today = now_th().date()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT DISTINCT wl.user_id
                   FROM work_logs wl
                   JOIN user_settings us ON us.user_id = wl.user_id
                   WHERE wl.logged_at::date = %s
                     AND wl.action LIKE %s
                     AND us.reminder_enabled = TRUE
                     AND wl.user_id NOT IN (
                         SELECT user_id FROM work_logs
                         WHERE logged_at::date = %s AND action LIKE %s
                     )""",
                (today, f"%{BTN_CHECKIN}%", today, f"%{BTN_CHECKOUT}%"),
            )
            return [row[0] for row in cur.fetchall()]


async def checkout_reminder_job(context: ContextTypes.DEFAULT_TYPE) -> None:
    user_ids = _get_unchecked_out_users()
    for uid in user_ids:
        try:
            await context.bot.send_message(
                chat_id=uid,
                text=(
                    "🔔 อันยองเตือนมาค่ะ🍑\n\n"
                    "ยังไม่ได้เช็คเอาท์เลยนะคะ ลืมหรือเปล่าคะ?\n"
                    "กดปุ่ม 🔴 เลิกงานแล้วน้า ได้เลยนะคะ~"
                ),
                reply_markup=MAIN_KEYBOARD,
            )
        except Exception:
            logger.warning("Failed to send reminder to user %d", uid)


# ---------------------------------------------------------------------------
# Error handler
# ---------------------------------------------------------------------------


async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    logger.error("Exception while handling update:", exc_info=context.error)
    if isinstance(update, Update) and update.message:
        try:
            await update.message.reply_text(
                "🍑 อุ๊บ~ เกิดข้อผิดพลาดค่ะ ลองใหม่อีกครั้งนะคะ~",
                reply_markup=MAIN_KEYBOARD,
            )
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Bot builder: register all handlers
# ---------------------------------------------------------------------------


async def more_menu_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Dispatch the inline 'more' menu buttons to the matching feature."""
    query = update.callback_query
    if not query or not query.message or not query.from_user:
        return
    await query.answer()
    msg = query.message
    user = query.from_user
    data = query.data
    if data == CB_SCRIPTS:
        await _send_scripts(msg)
    elif data == CB_CLIPS:
        await _send_clips(msg)
    elif data == CB_SUMMARY:
        await _send_summary(msg, user.id)
    elif data == CB_WORKS:
        await _send_works(msg, user.id)
    elif data == CB_PROFILE:
        await _send_profile(msg, user.id, user.full_name)
    elif data == CB_RANKING:
        await _send_ranking(msg)
    elif data == CB_EXPORT:
        await _send_export(msg, user.id)


def build_app(token: str, bot_name: str = "bot") -> Application:
    """Build and configure a telegram Application with all handlers."""
    app = Application.builder().token(token).build()

    # Conversation: commission calculator
    calc_conv = ConversationHandler(
        entry_points=[
            MessageHandler(filters.Regex(rf"^{re_escape(BTN_CALC)}$"), calc_start),
        ],
        states={
            CALC_AMOUNT: [MessageHandler(filters.TEXT & ~filters.COMMAND, calc_get_amount)],
            CALC_TYPE: [MessageHandler(filters.TEXT & ~filters.COMMAND, calc_get_type)],
        },
        fallbacks=[CommandHandler("cancel", calc_cancel)],
    )

    # Conversation: add script
    add_script_conv = ConversationHandler(
        entry_points=[CommandHandler("addscript", add_script_start)],
        states={
            ADD_SCRIPT_TEXT: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_script_save)],
        },
        fallbacks=[CommandHandler("cancel", add_cancel)],
    )

    # Conversation: add clip
    add_clip_conv = ConversationHandler(
        entry_points=[CommandHandler("addclip", add_clip_start)],
        states={
            ADD_CLIP_TITLE: [MessageHandler(filters.TEXT & ~filters.COMMAND, add_clip_save)],
        },
        fallbacks=[CommandHandler("cancel", add_cancel)],
    )

    # Conversation: broadcast
    broadcast_conv = ConversationHandler(
        entry_points=[CommandHandler("broadcast", broadcast_start)],
        states={
            BROADCAST_TEXT: [MessageHandler(filters.TEXT & ~filters.COMMAND, broadcast_send)],
        },
        fallbacks=[CommandHandler("cancel", add_cancel)],
    )

    # Register conversations first (higher priority)
    app.add_handler(calc_conv)
    app.add_handler(add_script_conv)
    app.add_handler(add_clip_conv)
    app.add_handler(broadcast_conv)

    # Commands
    app.add_handler(CommandHandler("anyong", anyong))
    app.add_handler(CommandHandler("start", anyong))
    app.add_handler(CommandHandler("help", anyong))
    app.add_handler(CommandHandler("logs", list_logs))
    app.add_handler(CommandHandler("clear", clear_logs))
    app.add_handler(CommandHandler("delscript", del_script))
    app.add_handler(CommandHandler("delclip", del_clip))
    app.add_handler(CommandHandler("summary", summary_cmd))
    app.add_handler(CommandHandler("ranking", ranking_cmd))
    app.add_handler(CommandHandler("export", export_cmd))
    app.add_handler(CommandHandler("works", works_cmd))
    app.add_handler(CommandHandler("profile", profile_cmd))
    app.add_handler(CommandHandler("stats", stats_cmd))
    app.add_handler(CommandHandler("reminder", reminder_cmd))

    # Callback queries (inline buttons)
    app.add_handler(CallbackQueryHandler(scripts_page_callback, pattern=r"^scripts_page_\d+$"))
    app.add_handler(CallbackQueryHandler(script_callback, pattern=r"^script_\d+$"))
    app.add_handler(CallbackQueryHandler(clips_page_callback, pattern=r"^clips_page_\d+$"))
    app.add_handler(CallbackQueryHandler(more_menu_callback, pattern=r"^menu_"))

    # Button presses & free text
    app.add_handler(MessageHandler(
        filters.Regex(rf"^({re_escape(BTN_SCRIPTS)})$"),
        menu_scripts,
    ))
    app.add_handler(MessageHandler(
        filters.Regex(rf"^({re_escape(BTN_CLIPS)})$"),
        menu_clips,
    ))
    # Free text + media captions (so 'name/amount' or links in photo captions
    # are parsed too).
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    app.add_handler(MessageHandler(
        (filters.PHOTO | filters.VIDEO | filters.Document.ALL) & filters.CAPTION,
        handle_message,
    ))

    # Error handler
    app.add_error_handler(error_handler)

    logger.info("Bot [%s] configured successfully", bot_name)
    return app


# ---------------------------------------------------------------------------
# Reminder scheduler
# ---------------------------------------------------------------------------


async def _schedule_reminders(app: Application) -> None:
    """Schedule the daily checkout reminder at 18:00 Bangkok time."""
    job_queue = app.job_queue
    if job_queue is None:
        logger.warning("JobQueue not available; reminders disabled")
        return
    reminder_time = datetime.now(TH_TZ).replace(hour=18, minute=0, second=0, microsecond=0).timetz()
    job_queue.run_daily(checkout_reminder_job, time=reminder_time, name="checkout_reminder")
    logger.info("Checkout reminder scheduled at 18:00 Bangkok time")


# ---------------------------------------------------------------------------
# Dual-bot runner
# ---------------------------------------------------------------------------


async def run_dual_bots() -> None:
    """Run one or two bots concurrently via asyncio."""
    init_db()

    apps: list[Application] = []

    app1 = build_app(TOKEN, "Bot-1")
    apps.append(app1)

    if TOKEN2:
        app2 = build_app(TOKEN2, "Bot-2")
        apps.append(app2)
        logger.info("Dual-bot mode: running 2 bots")
    else:
        logger.info("Single-bot mode: TOKEN2 not set")

    # Initialize all apps
    for app in apps:
        await app.initialize()
        await _schedule_reminders(app)
        await app.start()
        if app.updater:
            await app.updater.start_polling(
                drop_pending_updates=True,
                allowed_updates=Update.ALL_TYPES,
            )

    logger.info("All bots started — polling")

    # Block until interrupted
    stop_event = asyncio.Event()

    def _signal_handler() -> None:
        logger.info("Shutdown signal received")
        stop_event.set()

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _signal_handler)
        except NotImplementedError:
            pass

    await stop_event.wait()

    # Graceful shutdown
    logger.info("Shutting down bots...")
    for app in apps:
        if app.updater:
            await app.updater.stop()
        await app.stop()
        await app.shutdown()

    global _pool
    if _pool and not _pool.closed:
        _pool.closeall()
        logger.info("Database pool closed")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    # Keep-alive HTTP server in a daemon thread
    t = threading.Thread(target=run_keep_alive, daemon=True)
    t.start()

    try:
        asyncio.run(run_dual_bots())
    except KeyboardInterrupt:
        logger.info("Bot stopped by KeyboardInterrupt")
    except Exception:
        logger.exception("Fatal error in main")
        sys.exit(1)


if __name__ == "__main__":
    main()
