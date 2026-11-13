defmodule PuppyLogWeb.ProfileLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.Puppy

  setup :register_and_sign_in

  test "without a profile the profile page leads to the form", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/profile/edit"}}} = live(conn, ~p"/profile")
  end

  test "creates the profile with a photo", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/profile/edit")
    assert html =~ "Welpenprofil anlegen"

    photo =
      file_input(view, "#profile-form", :photo, [
        %{name: "bruno.jpg", content: "fake jpeg", type: "image/jpeg"}
      ])

    render_upload(photo, "bruno.jpg")

    assert {:ok, _view, html} =
             view
             |> form("#profile-form",
               form: %{
                 name: "Bruno",
                 birth_date: "2026-08-06",
                 breed: "Labrador",
                 chip_number: "276 098 106 543 210"
               }
             )
             |> render_submit()
             |> follow_redirect(conn, ~p"/profile")

    assert html =~ "Profil von Bruno gespeichert"
    assert html =~ "276 098 106 543 210"
    assert html =~ "6. August 2026"
    assert html =~ "Zuletzt geändert von Du"

    profile = Puppy.get_profile!(actor: user)
    assert profile.photo_path =~ ~r/\A[0-9a-f]{32}\.jpg\z/
    assert html =~ "/uploads/#{profile.photo_path}"
    on_exit(fn -> PuppyLog.Uploads.delete(profile.photo_path) end)
  end

  test "shows validation errors in German", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/profile/edit")

    html =
      view
      |> form("#profile-form", form: %{name: "Bruno", chip_number: "1234"})
      |> render_submit()

    assert html =~ "muss aus 15 Ziffern bestehen"
  end

  test "edits an existing profile", %{conn: conn, user: user} do
    {:ok, _} = Puppy.create_profile(%{name: "Bruno", breed: "Labrador"}, actor: user)

    {:ok, view, html} = live(conn, ~p"/profile/edit")
    assert html =~ "Profil bearbeiten"

    {:ok, _view, html} =
      view
      |> form("#profile-form", form: %{breed: "Labrador Retriever"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/profile")

    assert html =~ "Labrador Retriever"
  end

  test "edits the arrival date", %{conn: conn, user: user} do
    {:ok, _} = Puppy.create_profile(%{name: "Bruno"}, actor: user)

    {:ok, _view, html} = live(conn, ~p"/profile")
    assert html =~ "Einzug noch nicht eingetragen"

    {:ok, view, _html} = live(conn, ~p"/profile/edit")

    {:ok, _view, html} =
      view
      |> form("#profile-form", form: %{arrival_date: "2026-12-01"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/profile")

    assert html =~ "Eingezogen am 1. Dezember 2026"
  end
end
