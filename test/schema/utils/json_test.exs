defmodule Schema.Utils.JsonTest do
  use ExUnit.Case, async: true

  alias Schema.Utils.JSON

  describe "read!/1" do
    test "return a map with the file contents" do
      json = JSON.read!("test/data/container.json")
      assert map_size(json) > 0
    end
  end

  describe "file cache" do
    test "create and delete the cache table" do
      assert JSON.cache_init() == :ok
      assert JSON.cache_clear() == true
    end
  end
end