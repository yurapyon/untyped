\ : old-frame ." old" cr ;
\
\ ' old-frame value frame-hook
\
\ frame-hook execute
\
\ 1024 1024 * alloc-dictionary value sub-dict
\
\ sub-dict use-dictionary
\
\ : hello 1 2 3 . . . cr ;
\ : big-cr cr cr cr cr cr ;
\
\ ' hello to frame-hook
\
\ main-dictionary use-dictionary
\
\ frame-hook execute

false value yielded

\ start-corutine -> run ?

: exec-coroutine ( code -- xt/0 saved-stack/0 )
  false to yielded
  execute-forth-code
  yielded if
    false to yielded
    \ save the stack
  else
    0
  then
  ;

  \ TODO relies on Xt memory layout

: run ( xt -- xt/0 saved-stack/0 )
  expect forth-word?
  exec-coroutine
  ;

: yield true to yielded r> ;

: resume ( xt saved-stack -- xt/0 saved-stack/0 )
  \ restore stack
  cell - exec-coroutine
  ;

 : resumable
   ." before" cr
   yield
   ." after" cr
   ;

 : thingy
   ['] resumable run
   ." thing here" cr
   resume
   ;


 word resumable
 find drop 16 cells dump

\ ' yield

\ .s-debug

 thingy
