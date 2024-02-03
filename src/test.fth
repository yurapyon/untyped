: old-frame ." old" cr ;

' old-frame value frame-hook

frame-hook execute

1024 1024 * alloc-dictionary value sub-dict

sub-dict use-dictionary

: hello 1 2 3 . . . cr ;
: big-cr cr cr cr cr cr ;

' hello to frame-hook

main-dictionary use-dictionary

frame-hook execute
