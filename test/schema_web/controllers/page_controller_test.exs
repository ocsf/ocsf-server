defmodule SchemaWeb.PageControllerTest do
  use SchemaWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Splunk Event Schema"
  end
end
