' ==================== PhoneKeyboardKeys.brs ====================
' Key layout for PhoneKeyboardDialog's on-screen keyboard: 6x11 character
' grid (main block) + "easy keys" shortcuts block (right).
'
' Rows: numbers/dash | QWERTYUIOP: | ASDFGHJKL[] | CAPS+ZXCVBNM+BKSP |
' SHIFT+._+SPACE+#+cursors | symbols+/? | BACK/CLEAR/CANCEL/SAVE (action row).
'
' Dropped from the original 22-symbol wishlist to fit the 6x11 budget:
' comma, semicolon, apostrophe, asterisk.
'
' Key def fields: label/insert/action/isLetter/w/wpx.

function _pkdMainKeyRows() as Object
    return [
        [ { label: "1", insert: "1" }, { label: "2", insert: "2" }, { label: "3", insert: "3" }, { label: "4", insert: "4" }, { label: "5", insert: "5" }, { label: "6", insert: "6" }, { label: "7", insert: "7" }, { label: "8", insert: "8" }, { label: "9", insert: "9" }, { label: "0", insert: "0" }, { label: "-", insert: "-" } ],
        [ { label: "Q", insert: "q", isLetter: true }, { label: "W", insert: "w", isLetter: true }, { label: "E", insert: "e", isLetter: true }, { label: "R", insert: "r", isLetter: true }, { label: "T", insert: "t", isLetter: true }, { label: "Y", insert: "y", isLetter: true }, { label: "U", insert: "u", isLetter: true }, { label: "I", insert: "i", isLetter: true }, { label: "O", insert: "o", isLetter: true }, { label: "P", insert: "p", isLetter: true }, { label: ":", insert: ":" } ],
        [ { label: "A", insert: "a", isLetter: true }, { label: "S", insert: "s", isLetter: true }, { label: "D", insert: "d", isLetter: true }, { label: "F", insert: "f", isLetter: true }, { label: "G", insert: "g", isLetter: true }, { label: "H", insert: "h", isLetter: true }, { label: "J", insert: "j", isLetter: true }, { label: "K", insert: "k", isLetter: true }, { label: "L", insert: "l", isLetter: true }, { label: "[", insert: "[" }, { label: "]", insert: "]" } ],
        [ { label: "CAPS", action: "caps", w: 2 }, { label: "Z", insert: "z", isLetter: true }, { label: "X", insert: "x", isLetter: true }, { label: "C", insert: "c", isLetter: true }, { label: "V", insert: "v", isLetter: true }, { label: "B", insert: "b", isLetter: true }, { label: "N", insert: "n", isLetter: true }, { label: "M", insert: "m", isLetter: true }, { label: "BKSP", action: "backspace", w: 2 } ],
        [ { label: "SHIFT", action: "shift", w: 2 }, { label: ".", insert: "." }, { label: "_", insert: "_" }, { label: "SPACE", action: "space", w: 4 }, { label: "#", insert: "#" }, { label: "<", action: "cursorLeft" }, { label: ">", action: "cursorRight" } ],
        [ { label: "~", insert: "~" }, { label: "@", insert: "@" }, { label: "!", insert: "!" }, { label: "$", insert: "$" }, { label: "&", insert: "&" }, { label: "=", insert: "=" }, { label: "(", insert: "(" }, { label: ")", insert: ")" }, { label: "+", insert: "+" }, { label: "/", insert: "/" }, { label: "?", insert: "?" } ],
        [ { label: "BACK", action: "back", wpx: 278 }, { label: "CLEAR", action: "clear", wpx: 278 }, { label: "CANCEL", action: "cancel", wpx: 278 }, { label: "SAVE", action: "save", wpx: 278 } ]
    ]
end function

function _pkdShortcutKeyRows() as Object
    return [
        [ { label: "http://", insert: "http://" }, { label: "https://", insert: "https://" } ],
        [ { label: "www.", insert: "www." }, { label: ".com", insert: ".com" } ],
        [ { label: ".net", insert: ".net" }, { label: ".org", insert: ".org" } ]
    ]
end function
