-module(user_default).
-export([compile/0
        ,c/0
        ,deps/0
        ,path/0
        ,tree/0
        ,update/0
        ,version/0
        ,v/0]).


compile() -> r3:compile().
c()       -> r3:compile().


deps() -> r3:deps().


path() -> r3:path().


tree() -> r3:tree().


update() -> r3:update().


version() -> r3:version().
v()       -> r3:version().

