Kaleidogen
==========

http://kaleidogen.nomeata.de/


Local development with GHC
--------------------------

This does not require GHCJS.

* Install GHC-8.4 and an up-to-date version of `cabal`
* If ghc-8.4 is not just `ghc` in the path, add
  ```
  with-compiler: /path/to/ghc-8.4
  ```
  to `cabal.project.local`.
* Run `cabal update`
* Run `cabal new-build kaleidogen` to build
* Run `cabal new-run kaleidogen` to run a webserver at http://127.0.0.1:3003/
* Run `ghcid` if you have `ghcid` installed to run the webserver and
  automatically reload it upon code changes.

Building the SDL version
------------------------

There is also an SDL version. To build and run:

* Run `cabal new-run kaleidogen-sdl`

