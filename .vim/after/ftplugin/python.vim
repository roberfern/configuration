set tabstop=8
set softtabstop=8
set shiftwidth=8
set noexpandtab

match OverLength /\%1000v.\+/
set list
set listchars=tab:\|.,trail:-,nbsp:?
highlight SpecialKey ctermfg=Gray