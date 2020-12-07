" contextualize.vim tests
" Author:    Emilia Simmons

" Meant to be called: vim -u NONE -S tests.vim
" This is an /extremely/ basic test suite.

set nocompatible

function! Test_contexts() abort " {{{1
  ContextAdd emptyline EmptyLine
  ContextAdd nosurround <SNR>1_surroundingEmpty
  ContextAdd preva {-> getline('.')[col('.') - 2] == 'a'}
  call setline(1, ['', 'a  '])
  normal! G$
  call assert_true(contextualize#in('nosurround'))
  call assert_false(contextualize#in('preva'))
  normal! h
  call assert_true(contextualize#in('preva'))
  call assert_false(contextualize#in('emptyline'))
  normal! k
  call assert_true(contextualize#in('emptyline'))

  " ContextAdd <buffer> context s:surroundingEmpty
endfunction

function! EmptyLine() abort " {{{2
  return empty(getline('.'))
endfunction

function! s:surroundingEmpty() abort " {{{2
  return getline('.')[col('.') - 2 : col('.')] =~ '^\s*$'
endfunction

function! Test_incontexts() abort " {{{1
  ContextAdd emptyline {-> EmptyLine()}
  ContextAdd preva {-> getline('.')[col('.') - 2] == 'a'}
  call setline(1, ['', 'bbabb'])
  normal! gg
  call assert_true(contextualize#in('emptyline'))
  call assert_false(contextualize#in('preva'))
  normal! G$h
  call assert_false(contextualize#in('emptyline'))
  call assert_true(contextualize#in('preva'))
endfunction

function! Test_map() abort " {{{1
  Contextualize {-> EmptyLine()} inoremap b bb
  Contextualize {-> EmptyLine()} inoremap <buffer> c cc
  " normal obb
  call feedkeys('ob', 'mx')  " Must be separate
  call feedkeys('ab', 'mx')
  call assert_equal('bbb', getline('.'))
  call feedkeys('oc', 'mx')
  call feedkeys('ac', 'mx')
  call assert_equal('ccc', getline('.'))
  enew!
  call feedkeys('oc', 'mx')
  call feedkeys('ac', 'mx')
  call assert_equal('cc', getline('.'))
  Contextualize {-> EmptyLine()} inoremap <buffer> b bbb
  call feedkeys('ob', 'mx')
  call feedkeys('ab', 'mx')
  call assert_equal('bbbb', getline('.'))
  enew!
  call feedkeys('ob', 'mx')
  call feedkeys('ab', 'mx')
  call assert_equal('bbb', getline('.'))
endfunction

function! Test_unmap() abort " {{{1
  ContextAdd emptyline {-> EmptyLine()}
  ContextAdd preva {-> getline('.')[col('.') - 2] == 'a'}

  Contextualize emptyline inoremap b bb
  Contextualize preva inoremap b cc
  " Test delete all of them
  Decontextualize iunmap b
  call assert_equal({}, maparg('b', 'i', 0, 1))

  " Test removing single
  Contextualize emptyline inoremap b bb
  Contextualize preva inoremap b cc
  call feedkeys('iba', 'mx') " overall input: bab -> bbacc
  call feedkeys('ab', 'mx')
  Decontextualize emptyline iunmap b
  call feedkeys('ob', 'mx')
  Decontextualize preva iunmap b
  call assert_equal(getline(1), 'bbacc')
  call assert_equal(getline(2), 'b')
  call assert_equal({}, maparg('b', 'i', 0, 1))

  Contextualize emptyline inoremap b bb
  Contextualize emptyline inoremap c cc
  call assert_fails('Decontextualize emptyline')
  ContextDel emptyline
  call assert_equal({}, maparg('b', 'i', 0, 1))
  call assert_equal({}, maparg('c', 'i', 0, 1))
endfunction

" Run tests {{{1
let &runtimepath .= ',' . expand('<sfile>:p:h')
runtime plugin/contextualize.vim

let testFunctions = split(execute('function /Test_'), '\n')
call map(testFunctions, 'matchstr(v:val, ''^function \zs[^(]*'')')
call sort(testFunctions)


" let testFunctions = testFunctions[:3]
for test in testFunctions
  execute 'edit' tempname()
  try
    call {test}()
  catch
    call add(v:errors, 'Uncaught exception in: ' . v:exception . ' at ' . v:throwpoint)
  endtry
  if !empty(v:errors)
    echohl Error
    for err in v:errors
      echo err
    endfor
    echohl None
    let v:errors = []
  endif
  %bwipeout!
  let g:contexts = {}
  let g:contextualize = {}
  for mode in split('nvoicsxlt', '.\zs')
    execute mode . 'mapclear'
  endfor
endfor
echom 'Executed' len(testFunctions) 'tests.'
