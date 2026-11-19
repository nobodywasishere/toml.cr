require "big"
require "./spec_helper"

private enum Transport
  Tcp
  Udp
end

private struct Endpoint
  include TOML::Serializable

  @[TOML::Field(key: "listen-port")]
  getter port : UInt16
  getter address : String
  getter transport : Transport = Transport::Tcp
  getter? enabled : Bool = true

  def initialize(@port : UInt16, @address : String) : Nil
  end
end

private module MillisecondsConverter
  def self.from_toml(value : TOML::Any) : Time::Span
    value.as_i64.milliseconds
  end

  def self.to_toml(value : Time::Span) : Int64
    value.total_milliseconds.to_i64
  end
end

private class Settings
  include TOML::Serializable

  getter endpoints : Array(Endpoint)
  getter weights : Hash(String, Float32)
  getter extra : TOML::Any?
  getter revision : Int32 | String
  getter label : String?
  getter started : Time
  getter last_check : TOML::LocalDateTime
  getter day : TOML::LocalDate
  getter opens_at : TOML::LocalTime

  @[TOML::Field(converter: MillisecondsConverter)]
  getter timeout : Time::Span

  @[TOML::Field(ignore: true)]
  getter internal : Int32 = 0

  @[TOML::Field(ignore_serialize: !@verbose)]
  getter log_level : String = "info"

  @[TOML::Field(ignore_deserialize: true)]
  getter format_version : Int32 = 1

  getter? verbose : Bool = false

  protected def after_initialize
    @internal = @endpoints.size
  end
end

private struct StrictConfig
  include TOML::Serializable
  include TOML::Serializable::Strict

  getter title : String
end

private class TreeNode
  include TOML::Serializable

  getter name : String
  property children : Array(TreeNode) = [] of TreeNode

  def initialize(@name : String) : Nil
  end
end

private class NamedSection
  include TOML::Serializable

  getter name : String
end

private class PortsSection < NamedSection
  getter ports : Array(UInt16)

  def initialize(@name : String, @ports : Array(UInt16)) : Nil
  end
end

private struct OutputOnlySection
  include TOML::Serializable

  @[TOML::Field(ignore_deserialize: true)]
  getter section : NamedSection? = nil

  def initialize(@section : NamedSection) : Nil
  end
end

private struct TypedField(T)
  include TOML::Serializable

  getter value : T

  def initialize(@value : T) : Nil
  end
end

module UnionSpec
  struct DefaultSection
    include TOML::Serializable

    getter retries : Int32 = 3
  end

  struct NamedSection
    include TOML::Serializable
    include TOML::Serializable::Strict

    getter title : String
  end

  struct LimitSection
    include TOML::Serializable

    getter limit : Int64 | UInt64
  end

  struct IncompleteLimitSection
    include TOML::Serializable

    getter limit : Int64 | UInt64
    getter label : String
  end

  struct HookedItem
    include TOML::Serializable

    class_property calls : Int32 = 0

    getter value : Int32
    getter? decoded : Bool = false

    protected def after_initialize
      self.class.calls += 1
      @decoded = true
    end
  end

  struct HookedSection
    include TOML::Serializable

    getter items : Array(HookedItem)
  end

  struct TaggedHookedSection
    include TOML::Serializable

    getter items : Array(HookedItem)
    getter tag : String
  end

  module LookupConverter
    def self.from_toml(value : TOML::Any) : String
      value.as_h["key"].as_s
    end

    def self.to_toml(value : String) : Hash(String, String)
      {"key" => value}
    end
  end

  struct ConvertedSection
    include TOML::Serializable

    @[TOML::Field(converter: LookupConverter)]
    getter lookup : String
  end
end

private struct StrictOutputOnly
  include TOML::Serializable
  include TOML::Serializable::Strict

  @[TOML::Field(key: "schema-version", ignore_deserialize: true)]
  getter schema : Int32 = 1
end

private enum Mode
  FooBar
  FOO_BAR # ameba:disable Lint/EnumMemberNameConflict
end

private enum Status
  Ready

  def to_s : String
    "ready"
  end
end

@[Flags]
private enum Feature
  Read
  Write
  Execute

  def to_s : String
    "feature"
  end
end

private struct AliasedOutput
  include TOML::Serializable

  @[TOML::Field(key: "name")]
  property primary : String? = nil

  @[TOML::Field(key: "name", ignore_deserialize: true, ignore_serialize: !@emit_secondary)]
  property secondary : String? = nil

  @[TOML::Field(ignore: true)]
  property? emit_secondary : Bool = true

  def initialize(@primary : String?, @secondary : String?) : Nil
  end
end

private struct ConstantKey
  include TOML::Serializable
  include TOML::Serializable::Strict

  WIRE_KEY = "wire-key"

  @[TOML::Field(key: WIRE_KEY)]
  getter value : String
end

private struct ShadowedTypes
  include TOML::Serializable

  enum String
    Ready
  end

  struct Array
  end

  getter state : String
end

private class NonNilDefault
  include TOML::Serializable

  @[TOML::Field(key: "display-name")]
  property label : String? = "default"
end

private struct IgnoreFlags
  include TOML::Serializable

  ON  = true
  OFF = false

  @[TOML::Field(ignore: OFF, ignore_deserialize: OFF)]
  getter kept : String = "default"

  @[TOML::Field(ignore: ON)]
  getter hidden : String = "hidden"

  @[TOML::Field(ignore_deserialize: ON)]
  getter generated : String = "generated"
end

private class TaggedList < Array(Int32)
  getter tag : String = "tag"
end

private class TaggedMap < Hash(String, Int32)
  getter tag : String = "tag"
end

private abstract class Pet
  include TOML::Serializable
  getter name : String
end

private class Cat < Pet
  getter lives : Int32
end

private class Dog < Pet
  getter? tail : Bool
end

private class Fish < Pet
  getter fins : Int32
end

private struct PetOwner
  include TOML::Serializable
  getter pet : Cat | Dog
  getter companion : (Cat | Dog)?
end

module MappingSpec
  class BasePet
    include TOML::Serializable
    getter name : String
  end

  class Tabby < BasePet
    getter lives : Int32
  end

  class Hound < BasePet
    getter breed : String
  end

  class Owner
    include TOML::Serializable
    getter pet : Tabby | Hound
  end

  class Record < Owner
    getter id : Int32
  end

  alias Feline = Tabby

  struct AliasedOwner
    include TOML::Serializable
    getter pet : Tabby | Feline | Hound
  end

  struct MixedOwner
    include TOML::Serializable
    getter pet : Cat | Dog | String
  end

  module MixinFields
    KEY  = "mixin"
    SKIP = false

    @[TOML::Field(key: KEY, ignore_serialize: SKIP || @count.zero?)]
    getter count = 0
  end

  class OverridesMixinField
    include MixinFields
    include TOML::Serializable

    KEY = "model"

    @[TOML::Field(key: KEY)]
    getter count : Int32 = 3
  end

  struct ExplicitUnionOwner
    include TOML::Serializable
    getter pet : Union(Tabby, Hound)
  end

  struct Pack
    include TOML::Serializable
    getter pets : Array(Tabby | Hound)
  end

  alias TextOrTabby = String | Tabby

  struct AliasUnionOwner
    include TOML::Serializable
    getter pet : TextOrTabby | Hound
    getter companion : TextOrTabby | Tabby | Hound
  end

  class PlainParent
    KEY = "base"

    @[TOML::Field(key: KEY)]
    getter number = 0
  end

  class IncludesFields < PlainParent
    include MixinFields
    include TOML::Serializable
    include TOML::Serializable::Strict

    KEY  = "child"
    SKIP = true
  end

  class Parent
    include TOML::Serializable
    include TOML::Serializable::Strict

    KEY  = "original"
    SKIP = false

    @[TOML::Field(key: KEY, ignore: SKIP)]
    getter name : String = "fallback"

    @[TOML::Field(ignore_deserialize: SKIP, ignore_serialize: SKIP || @name.empty?)]
    getter label : String = "default"
  end

  class Child < Parent
    KEY  = "child"
    SKIP = true

    @[TOML::Field(key: KEY)]
    getter id : Int32
  end
end

describe TOML::Serializable do
  it "round-trips a class with nested structs and typed values" do
    settings = Settings.from_toml(<<-TOML)
      endpoints = [
        {"listen-port" = 80, address = "localhost", transport = "Udp", enabled = false},
        {"listen-port" = 443, address = "example.com"},
      ]
      weights = { "north.east" = 0.5 }
      extra = { mixed = [1, "two"] }
      revision = 8
      started = 2026-11-18T22:10:00-05:00
      last_check = 2026-11-18T22:10
      day = 2026-11-18
      opens_at = 08:30
      timeout = 125
      internal = 10
      format_version = 3
      unknown = "ignored"
      TOML

    settings.endpoints.map(&.port).should eq([80_u16, 443_u16])
    settings.endpoints.map(&.transport).should eq([Transport::Udp, Transport::Tcp])
    settings.endpoints.first.enabled?.should be_false
    settings.weights.should eq({"north.east" => 0.5_f32})
    settings.revision.should eq(8)
    settings.started.should eq(Time.utc(2026, 11, 19, 3, 10))
    settings.last_check.should eq(TOML::LocalDateTime.new(TOML::LocalDate.new(2026, 11, 18), TOML::LocalTime.new(22, 10)))
    settings.day.should eq(TOML::LocalDate.new(2026, 11, 18))
    settings.opens_at.should eq(TOML::LocalTime.new(8, 30))
    settings.timeout.should eq(125.milliseconds)
    settings.label.should be_nil
    settings.internal.should eq(2)
    settings.format_version.should eq(1)

    io = IO::Memory.new
    settings.to_toml(io)
    settings.to_toml.should eq(io.to_s)
    table = TOML.parse(io.to_s)
    table.should eq(settings.to_toml_table)
    table.has_key?("label").should be_false
    table.has_key?("internal").should be_false
    table.has_key?("log_level").should be_false
    table.has_key?("unknown").should be_false
    table["endpoints"][0]["listen-port"].as_i.should eq(80)
    io.rewind
    Settings.from_toml(io).to_toml_table.should eq(table)
    Settings.from_toml(table).extra.should eq(settings.extra)
  end

  it "serializes an instance created with an ordinary constructor" do
    endpoint = Endpoint.new(443_u16, "example.com")
    Endpoint.from_toml(endpoint.to_toml).address.should eq("example.com")
  end

  it "round-trips recursive structures and rejects cycles" do
    root = TreeNode.from_toml(%(name = "root"\nchildren = [{name = "child"}]))
    TreeNode.from_toml(root.to_toml).children.first.name.should eq("child")
    root.children << root
    expect_raises(TOML::SerializableError, /cyclic/) { root.to_toml }
  end

  it "round-trips inherited fields alongside a custom constructor" do
    section = PortsSection.new("local", [8080_u16])
    restored = PortsSection.from_toml(section.to_toml)
    restored.name.should eq("local")
    restored.ports.should eq([8080_u16])
  end

  it "round-trips a generic typed field" do
    binding = TypedField(Array(UInt16)).from_toml("value = [8080, 8443]")
    TypedField(Array(UInt16)).from_toml(binding.to_toml).value.should eq([8080_u16, 8443_u16])
  end

  it "rejects a union when multiple table types accept a value" do
    config = TypedField(UnionSpec::DefaultSection | UnionSpec::NamedSection).new(UnionSpec::NamedSection.from_toml(%(title = "local")))

    error = expect_raises(TOML::SerializableError, /field "value".*Ambiguous TOML value/) do
      typeof(config).from_toml(config.to_toml)
    end
    error.message.to_s.should contain("UnionSpec::DefaultSection")
    error.message.to_s.should contain("UnionSpec::NamedSection")

    typeof(config).from_toml("value = {retries = 10}").value.should be_a(UnionSpec::DefaultSection)
  end

  it "rejects a union when both the raw and a converted integer type fit" do
    expect_raises(TOML::SerializableError, /field "value".*Ambiguous TOML value/) do
      TypedField(Int64 | UInt64).from_toml("value = 123")
    end

    TypedField(Int64 | UInt64).from_toml("value = -1").value.should be_a(Int64)
    TypedField(Bool | Int32).from_toml("value = false").value.should be_false
  end

  it "does not fall back to a default-only table when a nested union is ambiguous" do
    expect_raises(TOML::SerializableError, /field "value".*field "limit".*Ambiguous TOML value/) do
      TypedField(UnionSpec::DefaultSection | UnionSpec::LimitSection).from_toml("value = {limit = 123}")
    end
  end

  it "discards a nested ambiguity when the candidate is missing another required field" do
    config = TypedField(UnionSpec::DefaultSection | UnionSpec::IncompleteLimitSection).from_toml("value = {limit = 123}")
    config.value.should be_a(UnionSpec::DefaultSection)
  end

  it "runs initialization hooks once for the selected member and never for ambiguous matches" do
    type = TypedField(UnionSpec::HookedSection | UnionSpec::TaggedHookedSection)
    UnionSpec::HookedItem.calls = 0
    config = type.from_toml("value = {items = [{value = 1}]}")
    config.value.items.first.decoded?.should be_true
    UnionSpec::HookedItem.calls.should eq(1)

    expect_raises(TOML::SerializableError, /Ambiguous TOML value/) do
      type.from_toml(%(value = {items = [{value = 1}], tag = "both"}))
    end
    UnionSpec::HookedItem.calls.should eq(1)
  end

  it "rejects subclasses in fields declared as a base class, including collection elements" do
    section = PortsSection.new("local", [8080_u16])
    expect_raises(TOML::SerializableError, /Cannot round-trip .*PortsSection as .*NamedSection/) do
      TypedField(NamedSection).new(section).to_toml
    end
    expect_raises(TOML::SerializableError, /Cannot round-trip .*PortsSection as .*NamedSection/) do
      TypedField(NamedSection | String).new(section).to_toml
    end
    expect_raises(TOML::SerializableError, /Cannot round-trip .*PortsSection as .*NamedSection/) do
      TypedField(Array(NamedSection) | String).new([section] of NamedSection).to_toml
    end
    expect_raises(TOML::SerializableError, /Cannot round-trip .*PortsSection as .*NamedSection/) do
      TypedField(Hash(String, NamedSection)).new({"section" => section} of String => NamedSection).to_toml
    end
  end

  it "lets the untyped builder write subclass fields" do
    section = PortsSection.new("local", [8080_u16])
    output = TOML.build do |builder|
      builder.field "sections", [section] of NamedSection
    end
    TOML.parse(output)["sections"][0]["ports"][0].as_i.should eq(8080)
  end

  it "lets output-only fields write subclass data" do
    config = OutputOnlySection.new(PortsSection.new("local", [8080_u16]))
    TOML.parse(config.to_toml)["section"]["ports"][0].as_i.should eq(8080)
    OutputOnlySection.from_toml(config.to_toml).section.should be_nil
  end

  it "wraps converter lookup errors with the field name" do
    error = expect_raises(TOML::SerializableError, /field "lookup".*Missing hash key/) do
      UnionSpec::ConvertedSection.from_toml("lookup = {}")
    end
    error.cause.should be_a(KeyError)
    config = TypedField(UnionSpec::DefaultSection | UnionSpec::ConvertedSection).from_toml("value = {lookup = {}}")
    config.value.should be_a(UnionSpec::DefaultSection)
  end

  it "round-trips exact enum names that normalize to the same string" do
    binding = TypedField(Mode).new(Mode::FOO_BAR)
    TypedField(Mode).from_toml(binding.to_toml).value.should eq(Mode::FOO_BAR)
    TypedField(Mode).from_toml(%(value = "FooBar")).value.should eq(Mode::FooBar)
  end

  it "writes declared enum names when the enum overrides its display text" do
    field = TypedField(Status).from_toml(%(value = "Ready"))
    field.to_toml.should eq(%(value = "Ready"\n))

    values = [Status::Ready, Feature::Read | Feature::Write]
    TOML.build(&.field("values", values)).should eq(%(values = ["Ready", "Read | Write"]\n))
  end

  it "round-trips flag combinations and rejects unnamed enum values on output" do
    [Feature::Read | Feature::Write, Feature::None, Feature::All].each do |flags|
      binding = TypedField(Feature).new(flags)
      TypedField(Feature).from_toml(binding.to_toml).value.should eq(flags)
    end

    expect_raises(TOML::SerializableError, /Cannot encode .* as TOML/) do
      TypedField(Feature).new(Feature.new(9)).to_toml
    end
    expect_raises(TOML::SerializableError, /Cannot encode .* as TOML/) do
      TypedField(Mode).new(Mode.new(9)).to_toml
    end
  end

  it "rejects nil inside an array" do
    binding = TypedField(Array(String?)).new([nil] of String?)
    expect_raises(TOML::SerializableError, /nil inside an array/) { binding.to_toml }
  end

  it "rejects two emitted fields with the same TOML alias" do
    fields = AliasedOutput.new("first", "second")
    io = IO::Memory.new

    expect_raises(TOML::SerializableError, /Duplicate TOML output key "name".*secondary/) { fields.to_toml(io) }
    io.to_s.should be_empty
  end

  it "allows a shared alias when only one field is emitted" do
    fields = AliasedOutput.new(nil, "second")
    fields.to_toml.should eq(%(name = "second"\n))

    fields.primary = "first"
    fields.emit_secondary = false
    fields.to_toml.should eq(%(name = "first"\n))
  end

  it "uses the boolean values of ignore constants in both directions" do
    model = IgnoreFlags.from_toml(%(kept = "custom"\nhidden = "input"\ngenerated = "input"))
    model.kept.should eq("custom")
    model.hidden.should eq("hidden")
    model.generated.should eq("generated")
    model.to_toml_table.should eq(TOML.parse(%(kept = "custom"\ngenerated = "generated")))
  end

  it "rejects unsupported ignore expressions at compile time" do
    source = File.join(__DIR__, "fixtures", "invalid_ignore_option.cr")
    output = IO::Memory.new
    status = Process.run("crystal", ["build", "--no-codegen", source], output: output, error: output)

    status.success?.should be_false
    output.to_s.should contain("TOML field value: ignore_deserialize must be a boolean literal or constant")
  end

  it "rejects collection subclasses that would lose their extra fields" do
    list = TaggedList.new
    list << 1
    map = TaggedMap.new
    map["one"] = 1
    expect_raises(TOML::SerializableError, /TaggedList.*field converter/) do
      TypedField(Array(Int32)).new(list).to_toml
    end
    expect_raises(TOML::SerializableError, /TaggedMap.*field converter/) do
      TypedField(Array(Hash(String, Int32))).new([map] of Hash(String, Int32)).to_toml
    end
  end

  it "round-trips the declared sibling classes and rejects ambiguous or unlisted shapes" do
    cat = PetOwner.from_toml(%(pet = {name = "kit", lives = 9}\ncompanion = {name = "pup", tail = true}))
    PetOwner.from_toml(cat.to_toml).companion.as(Dog).tail?.should be_true
    PetOwner.from_toml(cat.to_toml).pet.as(Cat).lives.should eq(9)
    dog = PetOwner.from_toml(%(pet = {name = "pup", tail = true}))
    PetOwner.from_toml(dog.to_toml).pet.as(Dog).tail?.should be_true
    expect_raises(TOML::SerializableError, /Ambiguous.*Cat.*Dog/) do
      PetOwner.from_toml(%(pet = {name = "both", lives = 9, tail = true}))
    end
    expect_raises(TOML::SerializableError, /field "pet"/) do
      PetOwner.from_toml(%(pet = {name = "fish", fins = 2}))
    end
  end

  it "preserves sibling fields when their common parent is concrete" do
    source = %(pet = {name = "Kit", lives = 9})
    owner = MappingSpec::Owner.from_toml(source)
    owner.pet.as(MappingSpec::Tabby).lives.should eq(9)
    TOML.parse(owner.to_toml).should eq(TOML.parse(source))
  end

  it "resolves inherited keys and ignore expressions in their declaring class" do
    source = %(original = "Kit"\nlabel = "saved"\nchild = 7)
    child = MappingSpec::Child.from_toml(source)
    child.name.should eq("Kit")
    child.label.should eq("saved")
    TOML.parse(child.to_toml).should eq(TOML.parse(source))
  end

  it "binds annotations from a mixin and a plain superclass to their respective scopes" do
    source = "base = 3\nmixin = 7"
    model = MappingSpec::IncludesFields.from_toml(source)
    TOML.parse(model.to_toml).should eq(TOML.parse(source))
    empty = MappingSpec::IncludesFields.from_toml("mixin = 0")
    TOML.parse(empty.to_toml).has_key?("mixin").should be_false
  end

  it "uses the model's annotation when it redeclares a mixin field" do
    model = MappingSpec::OverridesMixinField.from_toml("model = 8")
    model.count.should eq(8)
    model.to_toml_table.should eq(TOML.parse("model = 8"))
  end

  it "preserves sibling types declared with explicit Union syntax" do
    source = %(pet = {name = "Kit", lives = 9})
    owner = MappingSpec::ExplicitUnionOwner.from_toml(source)
    owner.pet.as(MappingSpec::Tabby).lives.should eq(9)
    TOML.parse(owner.to_toml).should eq(TOML.parse(source))
  end

  it "round-trips concrete sibling types inside a collection" do
    source = %(pets = [{name = "Kit", lives = 9}, {name = "Spot", breed = "beagle"}])
    pack = MappingSpec::Pack.from_toml(source)
    pack.pets[0].as(MappingSpec::Tabby).lives.should eq(9)
    pack.pets[1].as(MappingSpec::Hound).breed.should eq("beagle")
    TOML.parse(pack.to_toml).should eq(TOML.parse(source))
  end

  it "uses the concrete alternatives of a union-valued alias once on read and write" do
    source = %(pet = {name = "Kit", lives = 9}\ncompanion = {name = "Kat", lives = 8})
    owner = MappingSpec::AliasUnionOwner.from_toml(source)
    owner.pet.as(MappingSpec::Tabby).lives.should eq(9)
    owner.companion.as(MappingSpec::Tabby).lives.should eq(8)
    TOML.parse(owner.to_toml).should eq(TOML.parse(source))
  end

  it "retains the candidates of an inherited union getter" do
    source = %(id = 7\npet = {name = "Spot", breed = "beagle"})
    record = MappingSpec::Record.from_toml(source)
    record.pet.as(MappingSpec::Hound).breed.should eq("beagle")
    TOML.parse(record.to_toml).should eq(TOML.parse(source))
  end

  it "reads and writes both scalar and sibling alternatives of one union" do
    [%(pet = "unknown"), %(pet = {name = "Kit", lives = 9})].each do |source|
      owner = MappingSpec::MixedOwner.from_toml(source)
      TOML.parse(owner.to_toml).should eq(TOML.parse(source))
    end
  end

  it "tries aliases of the same concrete union member only once" do
    source = %(pet = {name = "Kit", lives = 9})
    owner = MappingSpec::AliasedOwner.from_toml(source)
    owner.pet.as(MappingSpec::Tabby).lives.should eq(9)
    TOML.parse(owner.to_toml).should eq(TOML.parse(source))
  end

  it "decodes scalar collections with the same range and type checks as scalar fields" do
    TypedField(Array(UInt8)).from_toml("value = [0, 255]").value.should eq([0_u8, 255_u8])
    TypedField(Hash(String, Status)).from_toml(%(value = {job = "Ready"})).value.should eq({"job" => Status::Ready})
    expect_raises(TOML::SerializableError, /field "value".*UInt8/) do
      TypedField(Array(UInt8)).from_toml("value = [255, 256]")
    end
    expect_raises(TOML::SerializableError, /field "value".*Status/) do
      TypedField(Hash(String, Status)).from_toml(%(value = {job = "Unknown"}))
    end
  end

  it "decodes a scalar array without allocating a plan for each element" do
    count = 100_000
    table = {"value" => TOML::Any.new(Array.new(count) { |i| TOML::Any.new(i) })}
    before = GC.stats.total_bytes
    values = TypedField(Array(Int32)).from_toml(table).value
    allocated = GC.stats.total_bytes - before

    values.size.should eq(count)
    values.last.should eq(count - 1)
    # Allow twice the output buffer size for allocator and model overhead.
    allocated.should be < (2 * count * sizeof(Int32))
  end

  it "reads and writes the string value of a constant field alias" do
    model = ConstantKey.from_toml(%("wire-key" = "ok"))
    model.value.should eq("ok")
    model.to_toml_table.keys.should eq(["wire-key"])
  end

  it "decodes nilable and multi-member unions with file-private members" do
    TypedField(Status?).from_toml("").value.should be_nil
    TypedField(Status?).from_toml(%(value = "Ready")).value.should eq(Status::Ready)
    type = TypedField(Array(Status | Endpoint))
    values = type.from_toml(%(value = ["Ready", {listen-port = 80, address = "localhost"}])).value
    values[0].should eq(Status::Ready)
    values[1].as(Endpoint).port.should eq(80)
  end

  it "decodes models whose nested types shadow standard library names" do
    document = %(state = "Ready"\n)
    model = ShadowedTypes.from_toml(document)
    model.state.should eq(ShadowedTypes::String::Ready)
    model.to_toml.should eq(document)
  end

  it "reports both fields when an input alias is shared" do
    source = File.join(__DIR__, "fixtures", "duplicate_input_alias.cr")
    output = IO::Memory.new
    status = Process.run("crystal", ["build", "--no-codegen", source], output: output, error: output)

    status.success?.should be_false
    output.to_s.should contain("Duplicate TOML input key \"shared\" for DuplicateInputAlias fields first and second")
  end

  it "rejects a nil field whose default would restore a value" do
    config = NonNilDefault.from_toml("")
    config.label.should eq("default")
    NonNilDefault.from_toml(config.to_toml).label.should eq("default")

    config.label = nil
    expect_raises(TOML::SerializableError, /field "display-name".*nil.*default/) { config.to_toml_table }
  end

  it "round-trips finite BigFloat fields and rejects unsupported magnitudes" do
    field = TypedField(BigFloat).from_toml("value = 1.25")
    field.value.should eq(BigFloat.new("1.25"))
    field.to_toml.should eq("value = 1.25\n")
    expect_raises(TOML::SerializableError) { TypedField(BigFloat).from_toml("value = inf") }
    expect_raises(TOML::SerializableError, /Float64/) { TypedField(BigFloat).new(BigFloat.new("1e500")).to_toml }
  end

  it "accepts a decimal that rounds to Float32::MAX" do
    TypedField(Float32).from_toml("value = 3.4028235e38").value.should eq(Float32::MAX)
    TypedField(Float32).from_toml("value = -3.4028235e38").value.should eq(-Float32::MAX)
  end

  it "accepts a declared output-only key in strict mode and ignores its input value" do
    config = StrictOutputOnly.from_toml("")
    config.to_toml.should eq("schema-version = 1\n")
    StrictOutputOnly.from_toml(config.to_toml).schema.should eq(1)
    StrictOutputOnly.from_toml("schema-version = 99").schema.should eq(1)
    expect_raises(TOML::SerializableError, /Unknown TOML field "schema"/) do
      StrictOutputOnly.from_toml("schema = 1")
    end
  end

  it "reports an out-of-range float" do
    expect_raises(TOML::SerializableError, /outside the range of Float32/) do
      TypedField(Float32).from_toml("value = 1e100")
    end
  end

  it "reports missing required fields" do
    expect_raises(TOML::SerializableError, /Missing TOML field "listen-port"/) do
      Endpoint.from_toml(%(address = "localhost"))
    end
  end

  it "reports type mismatches with the field name" do
    expect_raises(TOML::SerializableError, /field "listen-port".*Expected Int64, got String/) do
      Endpoint.from_toml(%(listen-port = "80"\naddress = "localhost"))
    end
  end

  it "reports an out-of-range integer" do
    expect_raises(TOML::SerializableError, /field "listen-port".*outside the range of UInt16/) do
      Endpoint.from_toml(%(listen-port = 65536\naddress = "localhost"))
    end
  end

  it "rejects unknown fields in strict mode" do
    StrictConfig.from_toml(%(title = "known")).title.should eq("known")
    expect_raises(TOML::SerializableError, /Unknown TOML field "extra"/) do
      StrictConfig.from_toml(%(title = "known"\nextra = false))
    end
  end
end
