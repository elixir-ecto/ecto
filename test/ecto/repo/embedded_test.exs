defmodule Ecto.Repo.EmbeddedTest do
  use ExUnit.Case, async: true

  alias Ecto.TestRepo, as: TestRepo

  defmodule SubEmbed do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :y, :string
    end
  end

  defmodule MyEmbed do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :x, :string
      embeds_one :sub_embed, SubEmbed, on_replace: :delete
      timestamps
    end
  end

  defmodule MyModel do
    use Ecto.Schema

    schema "my_model" do
      embeds_one :embed, MyEmbed, on_replace: :delete
      embeds_many :embeds, MyEmbed, on_replace: :delete
    end
  end

  @uuid "30313233-3435-3637-3839-616263646566"

  test "cannot change embeds on update_all" do
    changeset = Ecto.Changeset.change(%MyEmbed{})
    assert catch_error(TestRepo.update_all MyModel, set: [embed: %MyEmbed{}])
    assert catch_error(TestRepo.update_all MyModel, set: [embed: changeset])
  end

  ## insert

  test "adds embeds to changeset as empty on insert" do
    model = TestRepo.insert!(%MyModel{})
    assert model.embed == nil
    assert model.embeds == []
  end

  test "handles embeds on insert" do
    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, %MyEmbed{x: "xyz"})
    model = TestRepo.insert!(changeset)
    embed = model.embed
    assert embed.id
    assert embed.x == "xyz"
    assert embed.inserted_at

    changeset =
      %MyModel{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [%MyEmbed{x: "xyz"}])
    model = TestRepo.insert!(changeset)
    [embed] = model.embeds
    assert embed.id
    assert embed.x == "xyz"
    assert embed.inserted_at
  end

  test "handles embeds from struct on insert" do
    model = TestRepo.insert!(%MyModel{embed: %MyEmbed{x: "xyz"}})
    embed = model.embed
    assert embed.id
    assert embed.x == "xyz"
    assert embed.inserted_at

    model = TestRepo.insert!(%MyModel{embeds: [%MyEmbed{x: "xyz"}]})
    [embed] = model.embeds
    assert embed.id
    assert embed.x == "xyz"
    assert embed.inserted_at
  end

  test "handles invalid embeds from struct on insert" do
    {:error, changeset} = TestRepo.insert(%MyModel{embed: 1})
    assert changeset.errors == [embed: "is invalid"]
  end

  test "raises on action mismatch on insert" do
    changeset =
      %MyModel{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:embed, %MyEmbed{x: "xyz"})
    changeset = put_in(changeset.changes.embed.action, :update)
    assert_raise ArgumentError, ~r"got action :update in changeset for embedded .* while inserting", fn ->
      TestRepo.insert!(changeset)
    end
  end

  test "returns untouched changeset on constraint mismatch on insert" do
    changeset =
      put_in(%MyModel{}.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:embed, %MyEmbed{x: "xyz"})
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert changeset.model.__meta__.state == :built
    refute changeset.model.embed
    assert changeset.changes.embed
    refute changeset.changes.embed.model.id
    refute changeset.valid?
  end

  test "handles nested embeds on insert" do
    embed =
      %MyEmbed{x: "xyz"}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:sub_embed, %SubEmbed{y: "xyz"})
    changeset =
      %MyModel{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:embed, embed)
    model = TestRepo.insert!(changeset)
    assert model.embed.sub_embed.id
  end

  ## update

  test "skips embeds on update when not changing" do
    embed = %MyEmbed{x: "xyz"}

    # If embed is not in changeset, embeds are left out
    changeset = Ecto.Changeset.change(%MyModel{id: 1, embed: embed}, x: "abc")
    model = TestRepo.update!(changeset)
    assert model.embed == embed

    changeset = Ecto.Changeset.change(%MyModel{id: 1, embeds: [embed]}, x: "abc")
    model = TestRepo.update!(changeset)
    assert model.embeds == [embed]
  end

  test "inserting embeds on update" do
    changeset =
      %MyModel{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, %MyEmbed{x: "xyz"})
    model = TestRepo.update!(changeset)
    embed = model.embed
    assert embed.id
    assert embed.x == "xyz"
    assert embed.updated_at

    changeset =
      %MyModel{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [%MyEmbed{x: "xyz"}])
    model = TestRepo.update!(changeset)
    [embed] = model.embeds
    assert embed.id
    assert embed.x == "xyz"
    assert embed.updated_at
  end

  test "replacing embeds on update" do
    embed = %MyEmbed{x: "xyz", id: @uuid}

    # Replacing embed with a new one
    new_embed = %MyEmbed{x: "abc"}
    changeset =
      %MyModel{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, new_embed)
    model = TestRepo.update!(changeset)
    embed = model.embed
    assert embed.id != @uuid
    assert embed.x == "abc"
    assert embed.inserted_at
    assert embed.updated_at

    # Replacing embed with nil
    changeset =
      %MyModel{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, nil)
    model = TestRepo.update!(changeset)
    refute model.embed
  end

  test "changing embeds on update raises if there is no id" do
    embed = %MyEmbed{x: "xyz"}

    # Raises if there's no id
    embed_changeset = Ecto.Changeset.change(embed, x: "abc")
    changeset =
      %MyModel{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, embed_changeset)
    assert_raise Ecto.NoPrimaryKeyValueError, fn ->
      TestRepo.update!(changeset)
    end
  end

  test "changing embeds on update" do
    sample = %MyEmbed{x: "xyz", id: @uuid}
    sample_changeset = Ecto.Changeset.change(sample, x: "abc")

    changeset =
      %MyModel{id: 1, embed: sample}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, sample_changeset)
    model = TestRepo.update!(changeset)
    embed = model.embed
    assert embed.id == @uuid
    assert embed.x == "abc"
    refute embed.inserted_at
    assert embed.updated_at

    changeset =
      %MyModel{id: 1, embeds: [sample]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [sample_changeset])
    model = TestRepo.update!(changeset)
    [embed] = model.embeds
    assert embed.id == @uuid
    assert embed.x == "abc"
    refute embed.inserted_at
    assert embed.updated_at
  end

  test "empty changeset on update" do
    embed = %MyEmbed{x: "xyz", id: @uuid} |> Ecto.put_meta(state: :loaded)
    no_changes = Ecto.Changeset.change(embed)

    changeset =
      %MyModel{id: 1, embed: embed}
      |> Ecto.Changeset.change(x: "abc")
      |> Ecto.Changeset.put_embed(:embed, no_changes)
    model = TestRepo.update!(changeset)
    refute model.embed.updated_at

    changes = Ecto.Changeset.change(embed, x: "abc")
    changeset =
      %MyModel{id: 1, embeds: [embed]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [no_changes, changes])
    model = TestRepo.update!(changeset)
    refute hd(model.embeds).updated_at
  end

  test "removing embeds on update" do
    embed = %MyEmbed{x: "xyz", id: @uuid}

    changeset =
      %MyModel{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, nil)
    model = TestRepo.update!(changeset)
    assert model.embed == nil

    changeset =
      %MyModel{id: 1, embeds: [embed]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [])
    model = TestRepo.update!(changeset)
    assert model.embeds == []
  end

  test "returns untouched changeset on constraint mismatch on update" do
    embed = %MyEmbed{x: "xyz"}

    my_model = %MyModel{id: 1, embed: nil}
    changeset =
      put_in(my_model.__meta__.context, {:invalid, [unique: "my_model_foo_index"]})
      |> Ecto.Changeset.change(x: "foo")
      |> Ecto.Changeset.put_embed(:embed, embed)
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.update(changeset)
    refute changeset.model.embed
    assert changeset.changes.embed
    refute changeset.changes.embed.model.id
    refute changeset.valid?
  end

  test "handles nested embeds on update" do
    embed = %MyEmbed{id: @uuid, x: "xyz"}
    embed_changeset =
      embed
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:sub_embed, %SubEmbed{y: "xyz"})
    changeset =
      %MyModel{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, embed_changeset)
    model = TestRepo.update!(changeset)
    assert model.embed.sub_embed.id
  end

  ## delete

  test "embeds are not removed on delete" do
    embed = %MyEmbed{id: @uuid, x: "xyz"}

    model = TestRepo.delete!(%MyModel{id: 1, embed: embed})
    assert model.embed == embed

    model = TestRepo.delete!(%MyModel{id: 1, embeds: [embed]})
    assert model.embeds == [embed]
  end
end
