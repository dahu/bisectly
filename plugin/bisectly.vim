" Vim global plugin for locating faulty plugins
" Maintainer:	Barry Arthur <barry.arthur@gmail.com>
" Version:	0.2
" Description:	Plugin-manager agnostic fault locator using a BSFL algorithm.
" Last Change:	2013-04-06
" License:	Vim License (see :help license)
" Location:	plugin/bisectly.vim
" Website:	https://github.com/dahu/vim-bisectly
"
" See bisectly.txt for help.  This can be accessed by doing:
"
" :helptags ~/.vim/doc
" :help bisectly

let g:bisectly_version = '0.2'

" Vimscript Setup: {{{1
" Allow use of line continuation.
let s:save_cpo = &cpo
set cpo&vim

" if exists("g:loaded_bisectly")
"       \ || v:version < 700
"       \ || &compatible
"   let &cpo = s:save_cpo
"   finish
" endif
" let g:loaded_bisectly = 1

" Options: {{{1
if !exists('g:bisectly_log')
  let g:bisectly_log = expand('<sfile>:p:h:h') . '/bisectly.log'
endif

if !exists('g:vim_exe')
  let g:vim_exe = 'vim'
endif

" Private Functions: {{{1
function! Bisector(...)
  let b = {}
  let b.all = split(&rtp, '\\\@<!,')
  let b.rc_file = tempname() . '_bisectly.vimrc'
  let b.diagnostic = ''
  if a:0
    let b.diagnostic = a:1
  endif
  let b.vim_command = '!' . g:vim_exe . ' -N -u ' . b.rc_file
          \ . ' -c ' . shellescape('command! -bar Unicorns qa!', 1)
          \ . ' -c ' . shellescape('command! -bar U qa!', 1)
          \ . ' -c ' . shellescape('command! -bar Zombies cq!', 1)
          \ . ' -c ' . shellescape('command! -bar Z cq!', 1)
          \ . ' -c ' . shellescape(b.diagnostic, 1)
  if !exists('g:bisectly')
    let g:bisectly = {}
  endif
  let b.user_rc = get(g:bisectly, 'vimrc', '')
  let always_on = get(g:bisectly, 'always_on', '')
  if !empty(always_on)
    let b.always_on = filter(copy(b.all), 'v:val =~# always_on')
    call filter(b.all, 'v:val !~# always_on')
  else
    let b.always_on = []
  endif
  let b.on_before = filter(copy(b.always_on), 'fnamemodify(v:val, ":t") !=# "after"')
  call map(b.on_before, 'fnameescape(v:val)')
  let b.on_after = filter(copy(b.always_on), 'fnamemodify(v:val, ":t") ==# "after"')
  call map(b.on_after, 'fnameescape(v:val)')
  let always_off = get(g:bisectly, 'always_off', '')
  if !empty(always_off)
    call filter(b.all, 'v:val !~# always_off')
  endif

  func b.make_rc_file() dict abort
    let rtp = self.all[self.enabled[0] : self.enabled[1]]
    call map(rtp, 'fnameescape(v:val)')
    let on_before = [
          \ '" Always on:',
          \ 'set rtp='.join(self.on_before, ',')]
    let bisected_rtp = [
          \ '" Bisected &rtp:',
          \ 'set rtp+='.join(rtp, ',')]
    let on_after = [
          \ '" Always on (after directories):',
          \ 'set rtp+='.join(self.on_after, ',')]
    let user_rc = !empty(self.user_rc) && filereadable(self.user_rc)
          \ ? ['', '" Source user vimrc:', 'source ' . fnameescape(self.user_rc)]
          \ : []
    try
      call writefile((on_before + bisected_rtp + on_after + user_rc), self.rc_file)
    endtry
  endfunc

  func b.vim_test_run() dict
    call self.make_rc_file()
    silent! execute self.vim_command
    let self._shell_error = v:shell_error
  endfunc

  func b._read_log() dict
    if ! filereadable(g:bisectly_log)
      return []
    else
      return readfile(g:bisectly_log)
    endif
  endfunc

  func b._string(data) dict
    if type(a:data) == type([])
      return join(map(a:data, 'self._string(v:val)'), "\n")
    else
      return a:data
    endif
  endfunc

  func b._write_log(data) dict
    call writefile(split(self._string(a:data), "\n"), g:bisectly_log)
  endfunc

  func b.log(stuff) dict
    let data = self._read_log()
    call add(data, [strftime('%c')])
    call add(data, a:stuff)
    call self._write_log(data)
  endfunc

  func b.locate_fault(type) dict
    if a:type == 'binary'
      return self.bsfl()
    else
      return self.lsfl()
    endif
  endfunc

  func b.lsfl() dict
  endfunc

  func b.bsfl() dict
    let self.enabled = [0, len(self.all)]
    let self.disabled = []
    " prime the loop below sith a spurious shell_error to force division of
    " the enabled set of plugins
    let self._shell_error = 1

    " TODO: might need a better loop termination condition
    while self.enabled[0] != self.enabled[1]
      " halve the enabled range depending on v:shell_error.
      " v:shell_error == 1 when exited with :cq (:Zombies), meaning the user
      " considers this session to possess the pertinent fault.
      if self._shell_error == 0
        let range = self.disabled
        " no fault found, so we need to keep looking in the previously disabled
        " half
      else
        let range = self.enabled
        " the currently enabled half has the fault, so we need to keep looking
        " within it
      endif
      let half = range[0] + (range[1] - range[0]) / 2
      let self.enabled = [range[0], half]
      let self.disabled = [half + 1, range[1]]
      call self.log(["enabled:"] + self.all[self.enabled[0]:self.enabled[1]] + ["disabled:"] + self.all[self.disabled[0]:self.disabled[1]])
      call self.vim_test_run()
    endwhile

    if self._shell_error == 0
      return self.disabled[0]
    else
      return self.enabled[0]
    endif
  endfunc

  func b.report_fault(fault) dict
    if a:fault < len(self.all)
      echohl WarningMsg
      echom "Bisectly located a fault with: " . self.all[a:fault]
      echohl None
    else
      echohl ErrorMsg
      echom "Bisectly was unable to locate a fault."
      echohl None
    endif
  endfunc

  return b
endfunction

" Public Interface: {{{1
function! Bisectly(...)
  let locator = 'binary'
  let diagnostic = ''
  if a:0
    let locator = a:1
    if a:0 >= 2
      let diagnostic = join(a:000[1:])
    endif
  endif
  if locator !~? 'binary\|linear'
    throw 'Invalid locator: expecting "binary" or "linear"'
  endif
  let old_shell = &shell
  set shell=/bin/sh
  call delete(g:bisectly_log)
  let bisector = Bisector(diagnostic)
  let fault = bisector.locate_fault(locator)
  redraw!
  call bisector.report_fault(fault)
  let &shell = old_shell
endfunc

" Commands: {{{1
command! -nargs=* -complete=file Bisectly call Bisectly(<f-args>)

" Teardown:{{{1
"reset &cpo back to users setting
let &cpo = s:save_cpo

" vim: set sw=2 sts=2 et fdm=marker:
