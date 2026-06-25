;;; Directory Local Variables   -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

;; Point haskell-mode's interactive REPL at the Clash interactive shell
;; (`clashi`) instead of plain ghci, so `C-c C-l` loads the current buffer into
;; a clashi session.  `clashi` is `Clash.Main` run interactively, so it must be
;; *run* as an executable (`stack run clashi`), not loaded via `stack ghci`.
;;
;; Requires `interactive-haskell-mode' to be enabled in haskell-mode buffers
;; (that minor mode supplies the buffer<->REPL link and the C-c C-l binding);
;; this file only redirects which process gets spawned.
((haskell-mode
  . ((haskell-process-type . ghci)
     (haskell-process-path-ghci . "stack")
     (haskell-process-args-ghci . ("run" "clashi" "--" "-ferror-spans")))))
