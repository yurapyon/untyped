: interpret
word
2dup drop 0=
refill
find
if
immediate? if
>cfa ,
else
>cfa execute
then
else
>number if
state @ if
then
else
then
type
abort" word not found"
;

