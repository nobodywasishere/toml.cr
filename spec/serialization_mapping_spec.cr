require "./spec_helper"

private struct Bookmark
  include TOML::Serializable

  getter destination : URI
  getter mirrors : Array(URI)
end

private enum PaperSize
  HalfSheet
  FullSheet
end

private enum InkName
  DeepBlue
  DEEP_BLUE # ameba:disable Lint/EnumMemberNameConflict
end

@[Flags]
private enum Margins
  TopEdge
  BottomEdge
end

private struct SheetInventory
  include TOML::Serializable
  getter stock : Hash(PaperSize, Int32)
end

private struct FlexibleSheetInventory
  include TOML::Serializable
  getter stock : Hash(String, Int64) | Hash(PaperSize, Int64)
end

private struct PrintJob
  include TOML::Serializable

  @[TOML::Field(converter: TOML::Serializable::EnumConverter(PaperSize))]
  getter paper : PaperSize
  @[TOML::Field(converter: TOML::Serializable::FloatConverter(Float32))]
  getter scale : Float32
end

# Each key in the document names a pigment. Store quantities in milligrams.
@[TOML::Serializable::Options(converter: PigmentMapping)]
private record Pigments, amounts : Hash(String, Int64) do
  include TOML::Serializable
end

private module PigmentMapping
  def self.from_toml(table : TOML::Table) : Pigments
    Pigments.new(table.transform_values { |v| v.as_i64 * 1000 })
  end

  def self.to_toml(pigments : Pigments) : TOML::Table
    pigments.amounts.transform_values { |milligrams| TOML::Any.new(milligrams // 1000) }
  end
end

private struct ColorLabel
  include TOML::Serializable
  getter label : String
end

private struct PaintDescription
  include TOML::Serializable
  getter color : Pigments | ColorLabel
end

private struct PaintKit
  include TOML::Serializable
  getter pigments : Array(Pigments)
end

@[TOML::Serializable::Options(converter: TotalMapping)]
private record BatchTotal, grams : Int64 do
  include TOML::Serializable
  include TOML::Serializable::ReadOnly
end

private module TotalMapping
  def self.from_toml(table : TOML::Table) : BatchTotal
    BatchTotal.new(table.values.sum(&.as_i64))
  end
end

private struct BatchReport
  include TOML::Serializable
  getter total : BatchTotal
end

describe TOML::Serializable do
  it "round-trips URI fields and collection elements as strings" do
    source = %(destination = "https://example.org/a?q=b#c"\nmirrors = ["../local"])
    model = Bookmark.from_toml(source)
    model.destination.fragment.should eq("c")
    model.mirrors.should eq([URI.parse("../local")])
    Bookmark.from_toml(model.to_toml).should eq(model)
    expect_raises(TOML::SerializableError, /destination.*Expected String/) do
      Bookmark.from_toml("destination = 42\nmirrors = []")
    end
  end

  it "accepts integer and float inputs and enum aliases for opted-in fields" do
    model = PrintJob.from_toml(%(paper = "half_sheet"\nscale = 2))
    model.scale.should eq(2_f32)
    model.paper.should eq(PaperSize::HalfSheet)
    TOML.parse(model.to_toml)["scale"].raw.should be_a(Float64)
    PrintJob.from_toml(model.to_toml).should eq(model)
    expect_raises(TOML::SerializableError, /scale.*Float32/) do
      PrintJob.from_toml(%(paper = "FullSheet"\nscale = 1e80))
    end
  end

  it "preserves exact enum names and rejects ambiguous aliases" do
    codec = TOML::Serializable::EnumConverter(InkName)
    codec.from_toml(TOML::Any.new("DEEP_BLUE")).should eq(InkName::DEEP_BLUE)
    expect_raises(TOML::SerializableError, /Ambiguous/) { codec.from_toml(TOML::Any.new("deep_blue")) }
    flags = TOML::Serializable::EnumConverter(Margins)
    flags.from_toml(TOML::Any.new("top_edge | bottom_edge")).should eq(Margins::All)
  end

  it "maps enum table keys and rejects duplicate aliases" do
    inventory = SheetInventory.from_toml("[stock]\nhalf_sheet = 2")
    inventory.stock.should eq({PaperSize::HalfSheet => 2})
    inventory.to_toml.should eq("stock = {HalfSheet = 2}\n")
    SheetInventory.from_toml(inventory.to_toml).should eq(inventory)
    expect_raises(TOML::SerializableError, /Duplicate .* key/) do
      SheetInventory.from_toml("[stock]\nhalf_sheet = 2\nHalfSheet = 3")
    end
  end

  it "prefers exact string keys to enum aliases when selecting a union member" do
    inventory = FlexibleSheetInventory.from_toml("[stock]\nhalf_sheet = 2")
    inventory.stock.should eq({"half_sheet" => 2_i64})
  end

  it "uses a whole-table converter at the root and inside collections" do
    pigments = Pigments.from_toml(IO::Memory.new("ochre = 3"))
    pigments.amounts.should eq({"ochre" => 3000_i64})
    pigments.to_toml.should eq("ochre = 3\n")
    kit = PaintKit.from_toml("pigments = [{ochre = 3}]")
    kit.pigments.should eq([pigments])
    PaintKit.from_toml(kit.to_toml).should eq(kit)
  end

  it "tries the next union member when a whole-table converter rejects a value" do
    PaintDescription.from_toml(%(color = {label = "blue"})).color.should be_a(ColorLabel)
    expect_raises(TOML::SerializableError, /Pigments/) { Pigments.from_toml(%(ochre = "blue")) }
  end

  it "rejects writing read-only models at the root and inside another model" do
    report = BatchReport.from_toml("[total]\nred = 3\nblue = 5")
    report.total.grams.should eq(8)
    expect_raises(TOML::SerializableError, /BatchTotal is read-only/) { report.to_toml }
    io = IO::Memory.new
    expect_raises(TOML::SerializableError, /BatchTotal is read-only/) { report.total.to_toml(io) }
    io.empty?.should be_true
  end

  it "diagnoses unsupported field types on both read and write during semantic analysis" do
    source = File.join(__DIR__, "fixtures", "unsupported_toml_field.cr")
    [Array(String).new, ["-Dwrite_sample"]].each do |flags|
      output = IO::Memory.new
      status = Process.run("crystal", ["build", "--no-codegen", source] + flags, output: output, error: output)
      status.success?.should be_false
      output.to_s.should match(/Unsupported TOML (field|value) type InkSample; use a TOML field converter/)
    end
  end
end
