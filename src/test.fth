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

\ 0 cell    field stack-frame.ct
\   8 cells field stack-frame.buffer
\ constant stack-frame

\ 32 stack-frame * constant stack-frames-size
\ create stack-frames stack-frames-size allot

false value suspended

\ start-corutine -> run ?

: exec-coroutine ( code -- xt/0 saved-stack/0 )
  false to suspended
  \ save stack depth
  execute-forth-code
  suspended if
    false to suspended
    \ save the stack
  else
    0
  then
  ;


: run ( xt -- xt/0 saved-stack/0 )
  expect forth-word?
  \ TODO this relies on Xt memory layout
  \      basicaly we're telling forth to execute the type info of the xt
  \        but because it auto advances the program_ctr after calling zig functions
  \          this is handled automatically after calling executeForthCode
  exec-coroutine
  ;

: suspend true to suspended r> ;

: resume ( xt saved-stack -- xt/0 saved-stack/0 )
  \ restore stack
  cell - exec-coroutine
  ;

: in_here
  ." in here" cr
  suspend
  ." now here" cr
  ;

0 value here-ptr

: resumable
  ." rsm 1" cr
  suspend
  ['] in_here run
  to here-ptr
  suspend
  ." rsm 2" cr
  here-ptr resume
  ;

: thingy
  ['] resumable run
  resume
  resume
  ;

\ word resumable
\ find drop 16 cells dump

\ ' suspend

\ .s-debug

thingy
