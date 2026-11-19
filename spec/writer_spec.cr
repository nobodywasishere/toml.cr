require "big"
require "./spec_helper"

describe TOML do
  it "writes native Crystal hashes and arrays to an IO" do
    input = {"settings" => {"items" => [true, 1_i32, 0.5_f32, "text"]}}
    io = IO::Memory.new

    TOML.dump(input, io)

    io.to_s.should eq("settings = {items = [true, 1, 0.5, \"text\"]}\n")
    TOML.dump(input).should eq(io.to_s)
  end

  it "round-trips quoted keys and escaped strings" do
    key = "dot.in.key\n\"日本語\""
    value = "\\\"\0\b\t\n\f\r\e\u007f🧪"
    input = {key => Any.new(value), "" => Any.new("")}

    TOML.parse(TOML.dump(input)).should eq(input)
  end

  it "round-trips the value types of a parsed document" do
    input = TOML.parse(<<-TOML)
      instant = 1987-07-05T17:45:56.123456789+08:00
      local = 1987-07-05T17:45:56.123456789
      date = 1987-07-05
      time = 17:45:56.123456789
      numbers = [-9223372036854775808, 9223372036854775807, 1.0, -0.0, inf, -inf]
      map = {}
      [[tables]]
      array = []
      TOML

    decoded = TOML.parse(TOML.dump(input))
    decoded.should eq(input)
    (1.0 / decoded["numbers"][3].as_f).should eq(-Float64::INFINITY)
    TOML.parse(TOML.dump({"nan" => Float64::NAN}))["nan"].as_f.nan?.should be_true
  end

  it "writes an empty document for an empty root table" do
    TOML.dump(Table.new).should eq("")
  end

  it "writes a shared table at each occurrence" do
    shared = {"present" => true}
    TOML.dump({"first" => shared, "second" => shared})
      .should eq("first = {present = true}\nsecond = {present = true}\n")
  end

  it "rejects different key objects with equal text in root and inline tables" do
    table = {} of String => Int32
    table.compare_by_identity
    2.times { |i| table[String.new("key".to_slice)] = i }
    table.size.should eq(2)

    io = IO::Memory.new
    expect_raises(ArgumentError, /Duplicate TOML key "key"/) { TOML.dump(table, io) }
    io.to_s.should be_empty
    expect_raises(ArgumentError, /Duplicate TOML key "key"/) { TOML.dump({"nested" => table}) }
  end

  it "rejects cyclic data" do
    root = Table.new
    root["cycle"] = Any.new([Any.new(root)])

    expect_raises(ArgumentError, /cyclic/) { TOML.dump(root) }
  end

  it "rejects native integers outside the TOML integer range" do
    expect_raises(ArgumentError, /64-bit/) { TOML.dump({"number" => UInt64::MAX}) }
  end

  it "rejects finite BigFloats that overflow Float64" do
    [BigFloat.new("1e500"), BigFloat.new("-1e500")].each do |value|
      expect_raises(ArgumentError, /Float64/) { TOML.dump({"value" => value}) }
    end
    TOML.dump({"value" => BigFloat.new("1.25")}).should eq("value = 1.25\n")
  end

  it "rejects malformed UTF-8 in keys and strings" do
    invalid = String.new(Bytes[0xc0, 0x80])

    expect_raises(ArgumentError, /UTF-8/) { TOML.dump({invalid => ""}) }
    expect_raises(ArgumentError, /UTF-8/) { TOML.dump({"text" => invalid}) }
  end
end
