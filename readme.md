## Contextualize.vim

Everything needs a bit of context. Time to add some to your vim maps!

Contextualize.vim adds a few commands that provide a way to add
context-sensitive `map`s and `abbrev`s. The plugin just provides an interface
to do the bookkeeping for which `map` to use when.

This plugin heavily relies on `<Plug>` maps, so if you use `langmap`s, [it may
not work as intended](https://github.com/vim/vim/issues/5147). If you can
provide a test case, I would be happy to work with you to find a workaround!

### The basics

For a simple example, many people want a command line map or abbreviation to
function only at the start of the line:
```vim
cnoreabbrev <expr> h getcmdtype()==":" && getcmdline()=='h' ? 'vert help' : 'h'
```

To use contextualize.vim for this example, try:
```vim
" Load the plugin, required to use :ContextAdd and :Contextualize
packadd contextualize.vim
" Or runtime! plugin/contextualize.vim

" Define the context, which is able to take an argument if desired
ContextAdd startcmd {name -> getcmdtype()==":" && getcmdline()==name}
Contextualize startcmd h cnoreabbrev h vert help
Contextualize startcmd eft cnoreabbrev eft EditFtplugin
Contextualize startcmd w2 cnoreabbrev w2 w
" w2 for typos

" Edit the current filetype's ftplugin
command! -complete=filetype -nargs=? EditFtplugin execute 'edit ~/.vim/after/ftplugin/'
      \ . (empty(expand('<args>')) ? &filetype : expand('<args>')) . '.vim'
```

Function arguments for contexts are intended to be used as arguments
_at the time of creating the map_, as above.

There are 3 ways to create a context: using a lambda
expression in the `ContextAdd` command as above, using the function name in the
ContextAdd, or using a lambda expression in the Contextualize command before
the map command.

Here is a similar version of `startcmd` for each:
```vim
function! s:startcmd() abort dict
  return getcmdtype()==":" && getcmdline()==self.lhs
endfunction
ContextAdd namedfunctioncontext s:startcmd
Contextualize startcmd cnoreabbrev h vert help

ContextAdd startcmd-lambda {name -> getcmdtype()==":" && getcmdline()==name}
Contextualize startcmd-lambda h cnoreabbrev h vert help

Contextualize {-> getcmdtype()==":" && getcmdline()=='h'} cnoreabbrev h vert help
```

Note that:
1. A function context can be a dict function, and then has access to `self.lhs`
2. As before, in `startcmd-lambda` we specific what the name of this abbrev is
   Lambdas can not be dict functions in vim.
3. An anonymous context is not allowed arguments, and must be hardcoded
4. The contexts are checked in order of definition.

### Ultisnips

`<Tab>` is a valuable key, so if we want to set up some contexts for specific
uses while also using it for snippet expansion and jumping

``` vim
" Set up defaults
let g:UltiSnipsExpandTrigger = "<Plug>(myUltiSnipsExpand)"
let g:UltiSnipsJumpForwardTrigger = "<Plug>(myUltiSnipsForward)"
let g:UltiSnipsJumpBackwardTrigger = "<Plug>(myUltiSnipsBackward)"

imap <Tab> <Plug>(myUltiSnipsExpand)
xmap <Tab> <Plug>(myUltiSnipsExpand)

" Create autocmds for the context & context
augroup contextualize_ultisnips
  autocmd!
  autocmd User UltiSnipsEnterFirstSnippet let g:in_snippet = 1
  autocmd User UltiSnipsExitLastSnippet unlet! g:in_snippet
augroup END
ContextAdd insnippet {-> exists('g:in_snippet')}

" Set up maps
Contextualize insnippet imap <Tab> <Plug>(myUltiSnipsForward)
Contextualize insnippet imap <S-Tab> <Plug>(myUltiSnipsBackward)
Contextualize insnippet smap <Tab> <Plug>(myUltiSnipsForward)
Contextualize insnippet smap <S-Tab> <Plug>(myUltiSnipsBackward)

```
Now add any other `imap` for `<Tab>` that you want, and it won't disrupt
the control of ultisnips jumping with `<Tab>`.

For example,

```vim
ContextAdd pumvis {-> pumvisible()}
Contextualize pumvis inoremap <Cr> <C-y>
Contextualize pumvis inoremap <Tab> <C-n>
Contextualize pumvis inoremap <S-Tab> <C-p>
```

### Autopairs

We can use contextualize to create an autopairs setup, which allows for precise
control of how you want edge cases to function. Here is a base for how you could
start your own setup

``` vim
ContextAdd pairallowed {-> getline('.')[col('.') - 1] =~ '\W' || col('.') == col('$')}
ContextAdd completepair {close -> getline('.')[col('.') - 1] == close}
ContextAdd pairsurround {-> getline('.')[col('.') - 2 : col('.')] =~ '^\%(\V()\|{}\|[]\|''''\|""\)'}
ContextAdd quoteallowed {-> getline('.')[col('.') - 2 : col('.') - 1] !~ '\w'}

for pair in ['()', '[]', '{}']
  call contextualize#map('pairallowed' , 'i', 'map', pair[0], pair . '<C-g>U<Left>')
  call contextualize#map('pairallowed' , 's', 'map', pair[0], pair . '<C-g>U<Left>')
  call contextualize#map('completepair', 'i', 'map', pair[1], '<C-g>U<Right>', {'args': pair[1]})
endfor

Contextualize completepair ' inoremap ' <C-g>U<Right>
Contextualize completepair " inoremap " <C-g>U<Right>
Contextualize quoteallowed inoremap ' ''<C-g>U<Left>
Contextualize quoteallowed inoremap " ""<C-g>U<Left>
Contextualize quoteallowed snoremap ' ''<C-g>U<Left>
Contextualize quoteallowed snoremap " ""<C-g>U<Left>

Contextualize pairsurround inoremap <Bs> <BS><Del>
Contextualize pairsurround inoremap <Cr> <Cr><C-o>O
Contextualize pairsurround inoremap <Space> <Space><Space><C-g>U<Left>
```

1. `pairallowed` is true if the previous character is not a word character or the cursor is at the end of the line
2. `completepair` is true if the next character is the character we want to close with
3. `pairsurround` is true if the surrounding two characters are a pair
4. `quoteallowed` is true when neither of the surrounding characters are a word character

This is also an example of how to use the function interface to
contextualize.vim. See `:h contextualize-functions` for more.

Note that the order of the maps indicates their priority. So for quotes,
`completepair` maps should be defined first, otherwise you will get insertion
of additional quotes when you want them to be completed.
