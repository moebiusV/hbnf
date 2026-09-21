# Fiddle binding for the astbnf C config parser (tests/server.astbnf schema).
#
#   LD_LIBRARY_PATH=. ruby hbnfconf.rb valid.conf
require "fiddle"
require "json"

module HbnfConf
  HANDLE = Fiddle.dlopen(File.join(__dir__, "libhbnfconf.so"))
  CParseConfig = Fiddle::Function.new(HANDLE["parse_config"],
                                      [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  CConfPtr = Fiddle::Function.new(HANDLE["conf_ptr"],
                                  [], Fiddle::TYPE_VOIDP)

  # conf_ptr() returns a `server_t *`.  Layout (see conf.h):
  #   name (char* @ 0), listen{ iface (char* @ 8), port (uint16 @ 16) }, ...
  def self.parse_config(path)
    return nil unless CParseConfig.call(path) == 0

    s = CConfPtr.call
    name = s.ptr.to_s                 # char* at offset 0
    port = s[16, 2].unpack1("S")      # uint16_t at offset 16
    { name: name, port: port }
  end
end

if $PROGRAM_NAME == __FILE__
  puts JSON.pretty_generate(HbnfConf.parse_config(ARGV[0] || "valid.conf"))
end
