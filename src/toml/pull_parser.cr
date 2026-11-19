# A forward-only reader over an already parsed TOML value. Reading an object or
# array visits its children in document order. Consume each child once, or skip it.
class TOML::PullParser
  def initialize(value : Any) : Nil
    @pending = value.as(Any?)
  end

  def initialize(table : Table) : Nil
    initialize(Any.new(table))
  end

  def initialize(input : String | IO) : Nil
    initialize(TOML.parse(input))
  end

  def read_value : Any
    value = @pending || raise SerializableError.new("TOML value already consumed")
    @pending = nil
    value
  end

  def skip : Nil
    read_value
  end

  def read(type : T.class) : T forall T
    decoder = Serializable::Decoder.new
    decoder.finish(decoder.prepare(read_value, type))
  end

  def read_object(& : String ->) : Nil
    value = read_value.as_h? || raise SerializableError.new("Expected a TOML table")
    value.each do |key, child|
      @pending = child
      yield key
      finish
    end
  end

  def read_array(&) : Nil
    value = read_value.as_a? || raise SerializableError.new("Expected a TOML array")
    value.each do |child|
      @pending = child
      yield
      finish
    end
  end

  def read_string : String
    read(String)
  end

  def read_int : Int64
    read(Int64)
  end

  def read_float : Float64
    read(Float64)
  end

  def read_bool : Bool
    read(Bool)
  end

  # :nodoc:
  def finish : Nil
    raise SerializableError.new("TOML reader left a value unconsumed") if @pending
  end
end

class Array(T)
  def self.new(pull : TOML::PullParser) : self
    pull.read(self)
  end
end

class Hash(K, V)
  def self.new(pull : TOML::PullParser) : self
    pull.read(self)
  end
end

struct Enum
  def self.new(pull : TOML::PullParser) : self
    pull.read(self)
  end
end

{% for type in [String, Bool, Int8, Int16, Int32, Int64, Int128, UInt8, UInt16, UInt32, UInt64, UInt128, Float32, Float64, Time] %}
  def {{ type }}.new(pull : TOML::PullParser) : self
    pull.read(self)
  end
{% end %}

def Union.new(pull : TOML::PullParser) : self
  pull.read(self)
end
