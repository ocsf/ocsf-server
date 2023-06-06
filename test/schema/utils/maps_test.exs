defmodule SchemaTest.Utils.Maps do
  use ExUnit.Case, async: true

  alias Schema.Utils.Maps

  describe "merge_new/2" do
    test "return a map with the new value" do
      map1 = %{a: 1}
      map2 = %{b: 2}
      map3 = Maps.merge_new(map1, map2)
      assert map_size(map3) == 2
    end
    
    test "return unchanged map" do
      map1 = %{a: 1}
      map2 = %{a: 2}
      assert Maps.merge_new(map1, map2) == map1
    end
  end
  
  describe "put_new/2" do
    test "return a map with added map2 entry" do
      map1 = %{a: %{c: 1}, b: %{c: 2}}
      map2 = %{z: 2}
      map3 = Maps.put_new(map1, map2)
      assert map_size(map3) == 2
      assert get_in(map3, [:a, :z]) == Map.get(map2, :z)
    end
    
    test "return unchanged map" do
      map1 = %{a: %{c: 1}, b: %{c: 2}}
      map2 = %{c: 22}
      assert Maps.put_new(map1, map2) == map1
    end
  end
  
  describe "put_new_in/3" do
    test "return a map with added map2 entry" do
      map1 = %{a: %{b: %{c: 1}}}
      map2 = %{z: 22}
      map3 = Maps.put_new_in(map1, :a, map2)
      
      assert map_size(map3) == 1
      assert get_in(map3, [:a, :b, :z]) == Map.get(map2, :z)
    end
    
    test "return unchanged map" do
      map1 = %{a: %{b: %{c: 1, z: 2}}}
      map2 = %{z: 22}
      map3 = Maps.put_new_in(map1, :a, map2)

      assert map_size(map3) == 1
      assert get_in(map3, [:a, :b, :z]) == get_in(map1, [:a, :b, :z])
    end
  end
  
  describe "deep_merge/2" do
    test "return the left map when the right map is nil" do
      map = %{a: 1}
      assert Maps.deep_merge(map, nil) == map
    end

    test "return the right map when the left map has the same key" do
      map1 = %{a: 1}
      map2 = %{a: 2}
      assert Maps.deep_merge(map1, map2) == map2
    end

    test "return merged map" do
      map1 = %{a: 1, m: %{b: 2, c: 3}}
      map2 = %{b: 5, m: %{d: 6, c: 7}}
      map3 = Maps.deep_merge(map1, map2)

      assert map_size(map3) == 3
      assert Map.get(map3, :a) == Map.get(map1, :a)
      assert Map.get(map3, :b) == Map.get(map2, :b)
      assert get_in(map3, [:m, :c]) == get_in(map2, [:m, :c])
    end
  end
end
