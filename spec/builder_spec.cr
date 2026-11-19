require "./spec_helper"

describe TOML::Builder do
  it "builds a document with literal keys and typed values" do
    document = TOML.build do |builder|
      builder.field("site.name", "A \"quoted\" name")
      builder.field("created", Time.utc(2026, 11, 19))
      builder.field("limits", {"ram" => 128_i32})
      builder.table("server") do |server|
        server.field("enabled", true)
        server.field("port", 8080_u16)
      end
    end

    table = TOML.parse(document)
    table["site.name"].as_s.should eq(%(A "quoted" name))
    table["created"].raw.should eq(Time.utc(2026, 11, 19))
    table["limits"]["ram"].as_i.should eq(128)
    table["server"]["enabled"].as_bool.should be_true
    table["server"]["port"].as_i.should eq(8080)
  end

  it "builds heterogeneous arrays with nested tables and arrays" do
    document = TOML.build do |builder|
      builder.array("items") do |items|
        items.value(1)
        items.value("ready")
        items.table do |table|
          table.array("tags", &.value("one"))
        end
        items.array(&.value(false))
      end
    end

    items = TOML.parse(document)["items"]
    items[0].as_i.should eq(1)
    items[1].as_s.should eq("ready")
    items[2]["tags"][0].as_s.should eq("one")
    items[3][0].as_bool.should be_false
  end

  it "writes a completed document to an IO" do
    io = IO::Memory.new
    TOML.build(io) do |builder|
      builder.table("empty") { }
      builder.array("queue") { }
    end

    io.to_s.should eq("empty = {}\nqueue = []\n")
    TOML.build { }.should be_empty
  end

  it "preserves keys in separate scopes and rejects duplicate keys in the same table" do
    builder = TOML::Builder.new
    builder.table("section", &.field("enabled", false))
    builder.field("enabled", true)

    builder.to_toml_table["section"]["enabled"].as_bool.should be_false
    expect_raises(ArgumentError, /Duplicate TOML key "enabled"/) do
      builder.field("enabled", false)
    end
    builder.to_toml_table["enabled"].as_bool.should be_true
  end

  it "leaves the output untouched when the build block raises" do
    io = IO::Memory.new
    expect_raises(ArgumentError, /Duplicate TOML key/) do
      TOML.build(io) do |builder|
        builder.field("value", 1)
        builder.field("value", 2)
      end
    end
    io.to_s.should be_empty
  end

  it "rejects equal key text in a native identity hash" do
    table = {} of String => Int32
    table.compare_by_identity
    2.times { |i| table[String.new("key".to_slice)] = i }
    table.size.should eq(2)

    expect_raises(ArgumentError, /Duplicate TOML key "key"/) do
      TOML.build(&.field("nested", table))
    end
  end
end
