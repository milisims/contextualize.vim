syntax match vimContextAdd /\v^\s*Context(Add|Del)/  skipwhite nextgroup=vimContextNameOnly,vimOperParen
syntax match vimContextualize /^\s*Contextualize/ skipwhite nextgroup=vimContextName,vimContextAnon
syntax match vimContextNameOnly /\S\+/ contained
syntax match vimContextName   /\S\+/ contained skipwhite nextgroup=vimContextArg,vimContextMap
syntax match vimContextAnon /{.*}/ contained contains=vimOperParen skipwhite nextgroup=vimContextMap
syntax match vimContextArg   /\S\+/ contained skipwhite nextgroup=vimContextArg,vimContextMap
syntax match vimContextMap /\v<([nvoicsxlt])(nore|un)?(map|abbrev)>.*/ contained contains=vimMap,vimAbb skipwhite transparent

highlight link vimContextAdd Statement
highlight link vimContextualize Statement
highlight link vimContextName String
highlight link vimContextNameOnly String
