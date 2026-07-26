import string

from PyQt6.QtCore import Qt

QT_KEY_DICT = {}

for char in string.ascii_lowercase:
    upper_char = char.upper()
    QT_KEY_DICT[char] = eval("Qt.Key.Key_{}".format(upper_char))
    QT_KEY_DICT[upper_char] = eval("Qt.Key.Key_{}".format(upper_char))

for number in range(0, 10):
    QT_KEY_DICT[str(number)] = eval("Qt.Key.Key_{}".format(number))

QT_KEY_DICT.update({
    ":": Qt.Key.Key_Colon,
    ";": Qt.Key.Key_Semicolon,
    ".": Qt.Key.Key_Period,
    ",": Qt.Key.Key_Comma,
    "+": Qt.Key.Key_Plus,
    "-": Qt.Key.Key_Minus,
    "=": Qt.Key.Key_Equal,
    "_": Qt.Key.Key_Underscore,
    "[": Qt.Key.Key_BracketLeft,
    "]": Qt.Key.Key_BracketRight,
    "(": Qt.Key.Key_BraceLeft,
    ")": Qt.Key.Key_BraceRight,
    "{": Qt.Key.Key_ParenLeft,
    "}": Qt.Key.Key_ParenRight,
    "<": Qt.Key.Key_Less,
    ">": Qt.Key.Key_Greater,
    "@": Qt.Key.Key_At,
    "\\": Qt.Key.Key_Backslash,
    "|": Qt.Key.Key_Bar,
    "/": Qt.Key.Key_Slash,
    "#": Qt.Key.Key_NumberSign,
    "$": Qt.Key.Key_Dollar,
    "?": Qt.Key.Key_Question,
    '"': Qt.Key.Key_QuoteDbl,
    "`": Qt.Key.Key_QuoteLeft,
    "%": Qt.Key.Key_Percent,
    "^": Qt.Key.Key_AsciiCircum,
    "&": Qt.Key.Key_Ampersand,
    "*": Qt.Key.Key_Asterisk,
    "~": Qt.Key.Key_AsciiTilde,
    "!": Qt.Key.Key_Exclam,
    "'": Qt.Key.Key_Apostrophe,
    "SPC": Qt.Key.Key_Space,
    "RET": Qt.Key.Key_Return,
    "DEL": Qt.Key.Key_Backspace,
    "TAB": Qt.Key.Key_Tab,
    "<backtab>": Qt.Key.Key_Backtab,
    "<home>": Qt.Key.Key_Home,
    "<end>": Qt.Key.Key_End,
    "<left>": Qt.Key.Key_Left,
    "<right>": Qt.Key.Key_Right,
    "<up>": Qt.Key.Key_Up,
    "<down>": Qt.Key.Key_Down,
    "<prior>": Qt.Key.Key_PageUp,
    "<next>": Qt.Key.Key_PageDown,
    "<delete>": Qt.Key.Key_Delete,
    "<backspace>": Qt.Key.Key_Backspace,
    "<return>": Qt.Key.Key_Return,
    "<escape>": Qt.Key.Key_Escape
})

QT_TEXT_DICT = {
    "SPC": " ",
    "<return>": "RET",
    "<backtab>": "",
    "<home>": "",
    "<end>": "",
    "<left>": "",
    "<right>": "",
    "<up>": "",
    "<down>": "",
    "<prior>": "",
    "<next>": "",
    "<delete>": "",
    "<backspace>": "",
    "<escape>": ""
}

QT_MODIFIER_DICT = {
    "C": Qt.KeyboardModifier.ControlModifier,
    "M": Qt.KeyboardModifier.AltModifier,
    "S": Qt.KeyboardModifier.ShiftModifier,
    "s": Qt.KeyboardModifier.MetaModifier
}
