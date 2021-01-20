" contextualize.vim
" Author:    Emilia Simmons

let g:contexts = get(g:, 'contexts', {})
let g:contextualize = get(g:, 'contextualize', {})
let s:cmdregex = '\v<([nvoicsxlt])(nore|un)?(map|abbrev)>'

command! -nargs=+ ContextAdd call <SID>contextadd(expand('<sfile>'), <q-args>)
command! -nargs=+ ContextDel call <SID>contextdel(<q-args>)
command! -nargs=+ Contextualize call <SID>parse_and_map(expand('<sfile>'), <q-args>)
command! -nargs=+ Decontextualize call <SID>parse_and_unmap(<q-args>)
command! -nargs=+ InspectContextMap call <SID>inspect(<q-args>)

function! contextualize#add_context(cname, func, ...) abort " {{{1
  " Optional: buffer
  if get(a:, 1, 0)
    let b:contexts = get(b:, 'contexts', {})
    let contexts = b:contexts
  else
    let contexts = g:contexts
  endif

  if !has_key(contexts, a:cname)
    let contexts[a:cname] = {'func': a:func, 'maps': []}
    return
  endif

  " The context already exists, re evaluate each map with the new function, then set it up
  for mcname in contexts[a:cname].maps
    let map = eval(mcname).maps[a:cname]
    let map.func = function(a:func, map.args, map)
  endfor
  let contexts[a:cname] = {'func': a:func, 'maps': contexts[a:cname].maps}
endfunction

function! contextualize#del_context(cname, ...) abort " {{{1
  let buf = get(a:, 1, 0)
  try
    let contexts = buf ? b:contexts : g:contexts
  catch '^Vim\%((\a\+)\)\=:E121'
    echoerr 'No buffer contexts'
  endtry
  try
    for cmname in contexts[a:cname].maps
      let cm = eval(cmname)
      call contextualize#unmap(a:cname, cm.mode, cm.type, cm.lhs, cm.buffer)
    endfor
    unlet contexts[a:cname]
  catch '^Vim\%((\a\+)\)\=:E716'
    echoerr 'No context named:' a:cname
  endtry
endfunction

function! contextualize#in(name, ...) abort " {{{1
  return function(s:get_context(a:name).func, a:000)()
endfunction

function! contextualize#map(context, mode, type, lhs, rhs, ...) abort " {{{1
  " Optional argument, just one: a dict of these map options
  let contextmap = extend(copy(get(a:, 1, {})), {'noremap': 1, 'expr': 0, 'sid': 0, 'buffer': 0}, 'keep')
  call extend(contextmap, {'mode': a:mode, 'type': a:type, 'lhs': a:lhs, 'rhs': a:rhs})

  " Context args can be in the optional dict or in the context str for parsing later.
  let args = ''
  if !empty(get(contextmap, 'args', ''))
    let args = ' ' . contextmap.args
    unlet contextmap.args
  endif

  " Get mapcontroller and create/set default and other dict values if necessary
  let mapcontroller = s:get_mapcontroller(contextmap)
  if !has_key(mapcontroller, 'default')
    call extend(mapcontroller, {'maps': {},
          \ 'contexts': [],
          \ 'do': function('s:do'),
          \ 'type': contextmap.type,
          \ 'default': {},
          \ 'mode': contextmap.mode,
          \ 'lhs': contextmap.lhs,
          \ 'buffer': contextmap.buffer,
          \ }, 'keep')

    call s:make_default_map(mapcontroller)
  elseif a:context == 'default'
    call s:make_default_map(mapcontroller)
    let mapcontroller.default = s:make_plugmap('default', contextmap)
    return
  endif

  " Parse and set up context
  if a:context[0] == '{'
    let cname = 'ANON#' . sha256(a:context)[:8]
    let cargs = []
    try
      call s:get_context(cname)
    catch 'No context named'
      let prefix = (contextmap.buffer ? '<buffer> ' : '') . cname
      call s:contextadd(contextmap.sid, prefix . ' ' . a:context)
    endtry
    if !has_key(g:contexts, cname)
    endif
  else
    let [cname; cargs] = split(a:context . args)
  endif

  " Make the map and register it in context and the context with the map.
  let context = s:get_context(cname)
  let plugmap = s:make_plugmap(cname, contextmap)
  let plugmap.context = function(context.func, cargs, plugmap)
  let plugmap.args = cargs
  let mapcontroller.maps[cname] = plugmap
  if index(mapcontroller.contexts, cname) < 0
    call add(mapcontroller.contexts, cname)
    if mapcontroller.buffer
      let suffix = matchstr(mapcontroller.name, '^[bg]:contextualize\zs.*')
      let name = 'getbufvar(' . bufnr() . ", 'contextualize')" . suffix
    else
      let name = mapcontroller.name
    endif
    call add(context.maps, name)
  endif
endfunction

function! contextualize#unmap(cname, mode, type, lhs, ...) abort " {{{1
  " Unmap <plug>
  " Remove from mapcontroller
  " Remove from context[name].maps
  " If last map in mapcontroller, and default is lhs, then unmap lhs
  " If context is anonymous, and last map just removed, remove anon context
  let buffer = get(a:, 1, 0)
  let mapcontroller = s:get_mapcontroller({'buffer':buffer, 'lhs': a:lhs, 'mode': a:mode, 'type': a:type})
  let default = {'mode': mapcontroller.mode, 'lhs': mapcontroller.lhs, 'rhs': mapcontroller.lhs, 'noremap': 1}
  if a:cname == 'default'
    " Same as s:make_default_map
    let mapcontroller.default = s:make_plugmap('default', default)
    return
  endif

  let context = s:get_context(a:cname)
  let buf = buffer ? '<buffer> ' : ''
  try
    execute a:mode . 'unmap' buf . s:plugname(a:cname, a:lhs, buffer, 1)
  catch '^Vim\%((\a\+)\)\=:E\(24\|31\)'
    echoerr "No map found for: '" . a:mode . a:type buf . a:lhs . "' in context: '" . a:cname . "'"
  endtry
  call remove(mapcontroller.maps, a:cname)
  call remove(mapcontroller.contexts, index(mapcontroller.contexts, a:cname))
  call remove(context.maps, mapcontroller.name)

  let default = s:plugname('default', a:lhs, buffer, 1)
  if empty(mapcontroller.contexts) && mapcontroller.lhs == maparg(default, a:mode, 0, 1).rhs
    execute a:mode . 'un' . a:type buf . a:lhs
    execute a:mode . 'unmap' buf . default
    execute 'unlet' mapcontroller.name
  endif

endfunction

function! s:contextadd(sfile, qstr) abort " {{{1
  let parts = split(a:qstr)
  let buffer = parts[0] ==? '<buffer>'
  let [name; funcparts] = split(a:qstr)[buffer:]
  let text = join(funcparts)
  if name == 'default'
    try
      echoerr 'Unable to add context named ''default''.'
    endtry
  elseif text =~# '\<s:[[:alnum:]]'
    let sid = type(a:sfile) == v:t_string ? s:get_sid(a:sfile) : a:sfile
    let text = substitute(text, '\<s:\ze[[:alnum:]]', '<SNR>' . sid . '_', 'g')
  endif

  if funcparts[0] =~ '^{'
    try
      let Func = eval(text)
    catch '^Vim\%((\a\+)\)\=:E488'
      echoerr 'Contextualize: Anonymous contexts can not have arguments: "' . text . '"'
    endtry
  elseif len(funcparts) == 1
    let Func = function(text)
  else
    try
      echoerr 'Unable to parse context: ' . a:qstr
    endtry
  endif

  call contextualize#add_context(name, Func, buffer)
endfunction

function! s:contextdel(qargs) abort " {{{1
  " Deletes context & all maps that use that context
  " Clears maps if only default is left -- happens in unmap
  let buffer = a:qargs[0] =~? '^<buffer>'
  let contexts = buffer ? b:contexts : g:contexts
  let name = split(a:qargs)[buffer]
  call contextualize#del_context(name, buffer)
endfunction

function! s:do() abort dict " {{{1
  for context in self.contexts
    try
      if self.maps[context].context()
        return "\<Plug>" . self.maps[context].rhs[6:]
      endif
    catch '^Vim\%((\a\+)\)\=:E119'
      echoerr "Not enough arguments provided to context: '".context."' in map '".self.lhs."'"
    endtry
  endfor
  return "\<Plug>" . self.default.rhs[6:]
endfunction

function! s:get_context(name) abort " {{{1
  try
    return b:contexts[a:name]
  catch '^Vim\%((\a\+)\)\=:E\%(716\|121\)'  " Catch no key and b:contexts doesn't exist
    try
      return g:contexts[a:name]
    catch '^Vim\%((\a\+)\)\=:E716'  " Catch no key and b:contexts doesn't exist
      echoerr 'No context named:' a:name
    endtry
  endtry
endfunction

function! s:get_mapcontroller(contextmap) abort " {{{1
  " Get or make the dictionary and return
  if a:contextmap.buffer && !exists('b:contextualize')
    let b:contextualize = {}
  endif
  let lhsname = s:lower_keycodes(a:contextmap.lhs)
  let name = (a:contextmap.buffer ? 'b:' : 'g:') . 'contextualize'
  let mapdict = {name}
  for nxt in [a:contextmap.mode, a:contextmap.type]
    let mapdict[nxt] = get(mapdict, nxt, {})
    let mapdict = mapdict[nxt]
    let name .= '.' . nxt
  endfor
  let mapdict[lhsname] = get(mapdict, lhsname, {})
  let mapdict = mapdict[lhsname]
  let name .= "['" . substitute(lhsname, "'", "''", 'g') . "']"
  if empty(mapdict)
    let mapdict.name = name
  endif
  return mapdict
endfunction

function! s:get_sid(sname) abort " {{{1
  let scrname = fnamemodify(a:sname, ':p:~')
  if has_key(s:sid_cache, scrname)
    return s:sid_cache[scrname]
  endif

  redir => scnames
  silent scriptnames
  redir END
  let scnames = map(split(scnames, "\n"), 'split(v:val, ": ")')
  for [sid, fname] in scnames
    let s:sid_cache[fname] = str2nr(sid)
  endfor
  try
    return s:sid_cache[scrname]
  catch '^Vim\%((\a\+)\)\=:E716'
    echoerr 'No script name matching:' scrname
  endtry
endfunction
let s:sid_cache = {}

function! s:inspect(qargs) abort " {{{1
  " Parse a mapcmd and print the information int the mapcontroller for that lhs
  " contextname rhs
  let mapcontroller = s:get_mapcontroller(s:parse_mapcmd(a:qargs))
  let [mode, abbrev] = [mapcontroller.mode, mapcontroller.type == 'abbrev']
  echo (mapcontroller.name[0] == 'g' ? 'Global' : 'Buffer') 'map for' mapcontroller.lhs
  echo "Map controller at:" mapcontroller.name
  let rhs = map(copy(mapcontroller.maps), 'maparg("<Plug>" . s:lower_keycodes(v:val.rhs[6:], 1), mode, abbrev, 1)')
  let rhs.default = maparg("<Plug>" . s:lower_keycodes(mapcontroller.default.rhs[6:], 1), mode, abbrev, 1).rhs
  let namew = max(map(copy(mapcontroller.contexts) + ['default'], 'len(v:val)'))
  echo 'Context' repeat(' ', namew-5) 'rhs'
  for cname in mapcontroller.contexts
    echo '' cname . repeat(' ', namew-len(cname)) . ':  '  rhs[cname]['rhs']
  endfor
  echo ' default' . repeat(' ', namew - 7) . ':  '  rhs['default']
endfunction

function! s:lower_keycodes(name, ...) abort " {{{1
  " See :h keycodes. Lower'd to have consistent dictionary access
  " a:1 for returning <lt>tab> instead of <tab>, for mapping on rhs.
  let rep = '\=' . (get(a:, 1, 0) ? "'<lt>'" : "'<'") . ' . tolower(submatch(1)) . ">"'
  return substitute(a:name, s:keycodes, rep, 'g')
endfunction

let s:keycodes = '\v\<(' . join(['Nul', 'BS', '(S-)?Tab', 'NL', 'FF', 'CR', 'Return', 'Enter', 'Esc',
      \ 'Space', 'lt', 'Bslash', 'Bar', 'Del', 'CSI', 'xCSI', 'EOL', 'Ignore', 'NOP', 'Up', 'Down',
      \ 'Left', 'Right', 'S-Up', 'S-Down', 'S-Left', 'S-Right', 'C-Left', 'C-Right', 'Help',
      \ 'Undo', 'Insert', 'Home', 'End', 'PageUp', 'PageDown', 'kUp', 'kDown', 'kLeft', 'kRight',
      \ 'kHome', 'kEnd', 'kOrigin', 'kPageUp', 'kPageDown', 'kDel', 'kPlus', 'kMinus', 'kMultiply',
      \ 'kDivide', 'kPoint', 'kComma', 'kEqual', 'kEnter', 'k\d', '(S-)?F[1-9]', '(S-)?F1[012]',
      \ '[SCMAD]-.'
      \ ], '|') . ')\>'

function! s:make_default_map(mapcontroller) abort " {{{1
  " set up the default map for a mapcontroller, (extracted via 'maparg()'),
  " and execute 'map lhs contextualize.do()'
  let mc = a:mapcontroller

  let default = maparg(mc.lhs, mc.mode, mc.type == 'abbrev', 1)
  " if default is empty, there is no map (i.e 'j' moves down a line in normal mode)
  if empty(default) || default.rhs =~# '^[bg]:contextualize.*do()$'
    let default = {'mode': mc.mode, 'lhs': mc.lhs, 'rhs': mc.lhs, 'noremap': 1, 'buffer': mc.buffer}
  endif
  let mc.default = s:make_plugmap('default', default)
  " Bind s:do() as the map. Expr because we store the name of the map per context,
  " which vim then executes because this is an expression. Conveniently, an expr abbreviation
  " will execute a mapping, which allows this whole system to work.
  let opts = '<expr>' . (mc.buffer ? '<buffer>' : '')
  execute mc.mode . mc.type opts s:lower_keycodes(mc.lhs) s:lower_keycodes(mc.name, 1) . '.do()'
endfunction

function! s:make_plugmap(cname, contextmap) abort " {{{1
  " Execute "mapcmd <Plug>(contexualize-name-context) rhs" to create the map in context,
  " returns the dict with the incormation
  let cmd = a:contextmap.mode . (a:contextmap.noremap ? 'noremap' : 'map')
  for optn in ['expr', 'buffer', 'silent', 'nowait']
    let cmd .= get(a:contextmap, optn, 0) ? ' <' . optn . '>' : ''
  endfor
  let cmd .= ' ' . s:plugname(a:cname, a:contextmap.lhs, a:contextmap.buffer, 1)
  let cmd .= ' ' . a:contextmap.rhs
  execute cmd
  let mapinfo = {'lhs': a:contextmap.lhs, 'name': a:cname}
  let mapinfo.rhs = s:plugname(a:cname, a:contextmap.lhs, a:contextmap.buffer)
  return mapinfo
endfunction

function! s:plugname(cname, lhs, buffer, ...) abort " {{{2
  " a:1 is 'use <lt> for name?'
  let name = (a:buffer ? 'buffer' : 'global') .'-'. s:lower_keycodes(a:lhs, get(a:, 1, 0))
  return "<Plug>(contextualize-" . name . '-' . a:cname . ')'
endfunction

function! s:parse_and_map(sfile, qargs) abort " {{{1
  " Parse and map Contextualize commands: context mapcmd [opts] lhs rhs
  let [contextstr, cmdstr] = split(a:qargs, '\zs\s*\ze' . s:cmdregex)
  let opts = s:parse_mapcmd(cmdstr)
  let opts.sid = 0
  if opts.rhs =~? '<SID>'
    let opts.sid = s:get_sid(a:sfile)
    let opts.rhs = substitute(opts.rhs, '\c<SID>', '<SNR>' . opts.sid . '_', 'g')
  endif
  call contextualize#map(contextstr, opts.mode, opts.type, opts.lhs, opts.rhs, opts)
endfunction

function! s:parse_and_unmap(qargs) abort " {{{1
  " NO:
  " Decontextualize [context] --- use contextdel
  " YES:
  " Decontextualize [context] [unmapcmd lhs]
  " Decontextualize [unmapcmd lhs] -- unmaps all contexts
  " Decontextualize default [unmapcmd lhs] -- resets the default map

  let [cname; cmdstr] = split(a:qargs, '\zs\s*\ze' . s:cmdregex)
  if cname =~? '^' . s:cmdregex
    let cmdstr = [cname]
    let cname = ''
  endif

  let contextmap = s:parse_mapcmd(join(cmdstr))
  let [m, t, lhs, b] = [contextmap.mode, contextmap.type, contextmap.lhs, contextmap.buffer]
  if empty(cname)
    call contextualize#unmap('default', m, t, lhs, b)
    for cname in s:get_mapcontroller(contextmap).contexts
      call contextualize#unmap(cname, m, t, lhs, b)
    endfor
  else
    call contextualize#unmap(cname, m, t, lhs, b)
  endif

endfunction

function! s:parse_mapcmd(cmd) abort " {{{1
  " Parse map/abbrev command, returning a dict similar to maparg()
  " inoreabbrev <expr> lhs rhs -> {cmd: 'inoremap', mode: 'i', buffer: 0, type: 'abbrev', un: 0,
  " lhs: lhs, rhs:rhs, expr: 1}
  let splits = split(a:cmd)
  let [cmd, mode, nore, type] = matchlist(splits[0], '^' . s:cmdregex . '$')[:3]

  let contextmap = {'cmd': cmd,
        \ 'buffer': 0,
        \ 'mode': mode,
        \ 'noremap': nore == 'nore',
        \ 'type': type,
        \ 'un': nore == 'un', }

  if contextmap.type == 'map'
    let contextmap.silent = 0
  endif
  if empty(contextmap.un)
    let contextmap.expr = 0
    let contextmap.sid = 0
  endif

  let nosupport = empty(contextmap.un) ? '' : 'silent|expr'
  let nosupport = '\v(' . nosupport . 'nowait|script|unique)'
  for word in splits[1:]
    if word =~? '\v^\<(buffer|nowait|silent|script|expr|unique)'
      for wd in filter(split(word, '[><]'), '!empty(v:val)')
        if word =~? nosupport
          try
            echoerr 'Unsupported argument in ' . contextmap.type . ': <' . wd . '>'
          endtry
        endif
        let contextmap[wd] = 1
      endfor
    else
      let contextmap.lhs = word
      break
    endif
  endfor
  if !contextmap.un
    let contextmap.rhs = join(splits[index(splits, contextmap.lhs, 1) + 1 :])
  endif
  return contextmap
endfunction
