
" set ctags
set tags=tags

" table breaks into space
set tabstop=4
set expandtab

" open with last pos
set viminfo='10,\"100,:20,%,n~/.viminfo 
au BufReadPost * if line("'\"") > 0|if line("'\"") <= line("$")|exe("norm '\"")|else|exe "norm $"|endif|endif

" highlight & colorscheme
syntax on
set hlsearch
colorscheme desert

" no error sound
set noeb
set vb t_vb=
