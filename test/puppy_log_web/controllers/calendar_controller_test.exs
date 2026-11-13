defmodule PuppyLogWeb.CalendarControllerTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.{Accounts, Puppy}

  setup do
    pin_clock(DateTime.new!(~D[2026-11-13], ~T[10:00:00], "Europe/Berlin"))
    lukas = user_fixture(%{name: "Lukas"})
    riv = user_fixture(%{name: "Riv"})
    {:ok, lukas} = Accounts.rotate_calendar_token(lukas, actor: lukas)
    %{lukas: lukas, riv: riv}
  end

  defp vet_visit(actor, assignee, title) do
    Puppy.create_health_entry!(
      %{
        kind: :vet_visit,
        title: title,
        due_on: ~D[2026-11-20],
        due_time: ~T[10:00:00],
        assignee_id: assignee.id
      },
      actor: actor
    )
  end

  test "feed with valid token contains entries of both members", %{
    conn: conn,
    lukas: lukas,
    riv: riv
  } do
    {:ok, _} = Puppy.create_profile(%{name: "Bruno"}, actor: lukas)
    vet_visit(lukas, lukas, "Impfung beim Tierarzt")
    vet_visit(riv, riv, "Kontrolle")

    Puppy.create_health_entry!(%{kind: :deworming, title: "Uralt", due_on: ~D[2025-11-01]},
      actor: riv
    )

    body = conn |> get(~p"/calendar/#{lukas.calendar_token <> ".ics"}") |> response(200)

    assert body =~ "X-WR-CALNAME:Puppy Log – Bruno"
    assert body =~ "SUMMARY:Impfung beim Tierarzt"
    assert body =~ "Geht hin: Lukas"
    assert body =~ "SUMMARY:Kontrolle"
    assert body =~ "Geht hin: Riv"
    refute body =~ "Uralt"
  end

  test "calendar name falls back without a profile", %{conn: conn, lukas: lukas} do
    body = conn |> get("/calendar/#{lukas.calendar_token}.ics") |> response(200)
    assert body =~ "X-WR-CALNAME:Puppy Log\r\n"
  end

  test "unknown token is 404", %{conn: conn} do
    assert conn |> get("/calendar/nope.ics") |> response(404)
  end

  test "rotated token: old 404, new 200", %{conn: conn, lukas: lukas} do
    old = lukas.calendar_token
    {:ok, rotated} = Accounts.rotate_calendar_token(lukas, actor: lukas)

    assert rotated.calendar_token != old
    assert byte_size(rotated.calendar_token) == 43
    assert build_conn() |> get("/calendar/#{old}.ics") |> response(404)
    assert conn |> get("/calendar/#{rotated.calendar_token}.ics") |> response(200)
  end

  test "only the user themselves may rotate their token", %{lukas: lukas, riv: riv} do
    assert {:error, %Ash.Error.Forbidden{}} = Accounts.rotate_calendar_token(lukas, actor: riv)
    assert {:error, %Ash.Error.Forbidden{}} = Accounts.rotate_calendar_token(lukas)

    assert {:ok, %{id: id}} =
             Accounts.get_user_by_calendar_token(lukas.calendar_token, authorize?: false)

    assert id == lukas.id
  end

  test "content type text/calendar", %{conn: conn, lukas: lukas} do
    conn = get(conn, "/calendar/#{lukas.calendar_token}.ics")

    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["text/calendar; charset=utf-8"]
  end
end
