;; Hello WASI — reference WebAssembly plugin using the WASI Preview 1 ABI.
;;
;; The host invokes `_start` with argv = [pluginID, toolName, argsJSON].
;; The plugin writes its response JSON to stdout and exits with code 0.
;; A real plugin would read argv[1] / argv[2] to dispatch by tool; this
;; minimal demo always writes the same fixed message so the WASI bridge
;; itself is exercised end-to-end without dragging in JSON parsing or
;; libc.

(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; Layout:
  ;;   offset  0 .. 8  : iovec (buf ptr=64, buf len=29)
  ;;   offset  8 .. 12 : nwritten counter
  ;;   offset 64 ..    : the response bytes
  (data (i32.const 64) "{\"hello\":\"wasi\",\"ok\":true}\n")

  (func $_start (export "_start")
    ;; iovec.iov_base = 64
    i32.const 0
    i32.const 64
    i32.store
    ;; iovec.iov_len = 27 (length of the data block above)
    i32.const 4
    i32.const 27
    i32.store
    ;; fd_write(stdout=1, iovs=0, iovs_len=1, nwritten=8)
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 8
    call $fd_write
    drop
  )
)
