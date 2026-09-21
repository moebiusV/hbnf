;; newLISP FFI binding for the astbnf C config parser (tests/server.astbnf).
;; Build libserver.so first, then:
;;   (load "server.lsp")
;;   (server:parse "valid.conf")
;;
;; Layout of the returned server_t (see conf.h): name is a char* at offset 0,
;; listen.iface a char* at offset 8, listen.port a uint16 at offset 16.
(context 'server)

(import "libserver.so" "parse_config")
(import "libserver.so" "conf_ptr")

(define (parse path)
  (if (= (parse_config path) 0)
      (let (p (conf_ptr) np (get-long p))
        (list 'name (get-string np)
              'iface (get-string (get-long (+ p 8)))
              'port (& (get-int (+ p 16)) 0xFFFF)))))

(context MAIN)
