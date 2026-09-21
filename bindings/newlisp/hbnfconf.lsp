;; newLISP FFI binding for the astbnf C config parser (tests/server.astbnf).
;; Build libhbnfconf.so first, then:
;;   (load "hbnfconf.lsp")
;;   (hbnfconf:parse "valid.conf")
;;
;; Layout of the returned server_t (see conf.h): name is a char* at offset 0,
;; listen.iface a char* at offset 8, listen.port a uint16 at offset 16.
(context 'hbnfconf)

(import "libhbnfconf.so" "parse_config")
(import "libhbnfconf.so" "conf_ptr")

(define (parse path)
  (if (= (parse_config path) 0)
      (let (p (conf_ptr) np (get-long p))
        (list 'name (get-string np)
              'iface (get-string (get-long (+ p 8)))
              'port (& (get-int (+ p 16)) 0xFFFF)))))

(context MAIN)
