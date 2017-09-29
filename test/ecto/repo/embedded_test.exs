defmodule Ecto.Repo.EmbeddedTest do
  use ExUnit.Case, async: true

  alias Ecto.TestRepo, as: TestRepo

  defmodule SubEmbed do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :y, :string
    end
  end

  defmodule MyEmbed do
    use Ecto.Schema

    embedded_schema do
      field :x, :string
      embeds_one :sub_embed, SubEmbed, on_replace: :delete
      timestamps()
    end
  end

  defmodule MyAssoc do
    use Ecto.Schema

    schema "my_assocs" do
      field :x
      field :my_assoc_id
    end
  end

  defmodule MySchema do
    use Ecto.Schema

    schema "my_schema" do
      embeds_one :embed, MyEmbed, on_replace: :delete
      embeds_many :embeds, MyEmbed, on_replace: :delete
      has_one :assoc, MyAssoc
    end
  end

  @uuid "30313233-3435-4637-9839-616263646566"

  ## insert

  test "adds embeds to changeset as empty on insert" do
    schema = TestRepo.insert!(%MySchema{})
    assert schema.embed == nil
    assert schema.embeds == []
  end

  test "handles embeds on insert" do
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, %MyEmbed{x: "xyz"})
    schema = TestRepo.insert!(changeset)
    embed = schema.embed
    assert embed.id
    assert embed.x == "xyz"
    assert embed.inserted_at

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [%MyEmbed{x: "xyz"}])
    schema = TestRepo.insert!(changeset)
    [embed] = schema.embeds
    assert embed.id
    assert embed.x == "xyz"
    assert embed.inserted_at
  end

  test "handles embeds from struct on insert" do
    schema = TestRepo.insert!(%MySchema{embed: %MyEmbed{x: "xyz"}})
    embed = schema.embed
    assert embed.id
    assert embed.x == "xyz"
    assert embed.inserted_at

    schema = TestRepo.insert!(%MySchema{embeds: [%MyEmbed{x: "xyz"}]})
    [embed] = schema.embeds
    assert embed.id
    assert embed.x == "xyz"
    assert embed.inserted_at
  end

  test "handles invalid embeds from struct on insert" do
    {:error, changeset} = TestRepo.insert(%MySchema{embed: 1})
    assert changeset.errors == [embed: "is invalid"]
  end

  test "returns untouched changeset on constraint mismatch on insert" do
    changeset =
      put_in(%MySchema{}.__meta__.context, {:invalid, [unique: "my_schema_foo_index"]})
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:embed, %MyEmbed{x: "xyz"})
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.insert(changeset)
    assert changeset.data.__meta__.state == :built
    refute changeset.data.embed
    assert changeset.changes.embed
    refute changeset.changes.embed.data.id
    refute changeset.valid?
  end

  test "returns untouched changeset on invalid child association" do
    invalid_assoc =
      put_in(%MyAssoc{}.__meta__.context, {:invalid, [unique: "my_assocs_foo_index"]})
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint(:foo)

    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_assoc(:assoc, invalid_assoc)
      |> Ecto.Changeset.put_embed(:embed, %MyEmbed{x: "xyz"})

    {:error, changeset} = TestRepo.insert(changeset)
    assert %Ecto.Changeset{} = changeset.changes.embed
  end

  test "handles nested embeds on insert" do
    embed =
      %MyEmbed{x: "xyz"}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:sub_embed, %SubEmbed{y: "xyz"})
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:embed, embed)
    schema = TestRepo.insert!(changeset)
    assert schema.embed.sub_embed.y == "xyz"
  end

  test "duplicate pk on insert" do
    embeds = [%MyEmbed{x: "xyz", id: @uuid} |> Ecto.Changeset.change,
              %MyEmbed{x: "abc", id: @uuid} |> Ecto.Changeset.change]
    changeset =
      %MySchema{}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, embeds)
    assert {:error, changeset} = TestRepo.insert(changeset)
    refute changeset.valid?
    errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    assert errors == %{embeds: [%{}, %{id: ["has already been taken"]}]}
  end

  ## update

  test "skips embeds on update when not changing" do
    embed = %MyEmbed{x: "xyz"}

    # If embed is not in changeset, embeds are left out
    changeset = Ecto.Changeset.change(%MySchema{id: 1, embed: embed}, x: "abc")
    schema = TestRepo.update!(changeset)
    assert schema.embed == embed

    changeset = Ecto.Changeset.change(%MySchema{id: 1, embeds: [embed]}, x: "abc")
    schema = TestRepo.update!(changeset)
    assert schema.embeds == [embed]
  end

  test "inserting embeds on update" do
    changeset =
      %MySchema{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, %MyEmbed{x: "xyz"})
    schema = TestRepo.update!(changeset)
    embed = schema.embed
    assert embed.id
    assert embed.x == "xyz"
    assert embed.updated_at

    changeset =
      %MySchema{id: 1}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [%MyEmbed{x: "xyz"}])
    schema = TestRepo.update!(changeset)
    [embed] = schema.embeds
    assert embed.id
    assert embed.x == "xyz"
    assert embed.updated_at
  end

  test "replacing embeds on update" do
    embed = %MyEmbed{x: "xyz", id: @uuid}

    # Replacing embed with a new one
    new_embed = %MyEmbed{x: "abc"}
    changeset =
      %MySchema{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, new_embed)
    schema = TestRepo.update!(changeset)
    embed = schema.embed
    assert embed.id != @uuid
    assert embed.x == "abc"
    assert embed.inserted_at
    assert embed.updated_at

    # Replacing embed with nil
    changeset =
      %MySchema{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, nil)
    schema = TestRepo.update!(changeset)
    refute schema.embed
  end

  test "changing embeds on update raises if there is no id" do
    embed = %MyEmbed{x: "xyz"}

    # Raises if there's no id
    embed_changeset = Ecto.Changeset.change(embed, x: "abc")
    changeset =
      %MySchema{id: 1, embed: embed}
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
      %MySchema{id: 1, embed: sample}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, sample_changeset)
    schema = TestRepo.update!(changeset)
    embed = schema.embed
    assert embed.id == @uuid
    assert embed.x == "abc"
    refute embed.inserted_at
    assert embed.updated_at

    changeset =
      %MySchema{id: 1, embeds: [sample]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [sample_changeset])
    schema = TestRepo.update!(changeset)
    [embed] = schema.embeds
    assert embed.id == @uuid
    assert embed.x == "abc"
    refute embed.inserted_at
    assert embed.updated_at
  end

  test "empty changeset on update" do
    embed = %MyEmbed{x: "xyz", id: @uuid}
    no_changes = Ecto.Changeset.change(embed)

    changeset =
      %MySchema{id: 1, embed: embed}
      |> Ecto.Changeset.change(x: "abc")
      |> Ecto.Changeset.put_embed(:embed, no_changes)
    schema = TestRepo.update!(changeset)
    refute schema.embed.updated_at

    changes = Ecto.Changeset.change(%MyEmbed{x: "xyz", id: "30313233-3435-3637-3839-616263646567"}, x: "abc")
    changeset =
      %MySchema{id: 1, embeds: [embed]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [no_changes, changes])
    schema = TestRepo.update!(changeset)
    refute hd(schema.embeds).updated_at
  end

  test "removing embeds on update" do
    embed = %MyEmbed{x: "xyz", id: @uuid}

    changeset =
      %MySchema{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, nil)
    schema = TestRepo.update!(changeset)
    assert schema.embed == nil

    changeset =
      %MySchema{id: 1, embeds: [embed]}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embeds, [])
    schema = TestRepo.update!(changeset)
    assert schema.embeds == []
  end

  test "returns untouched changeset on constraint mismatch on update" do
    embed = %MyEmbed{x: "xyz"}

    my_schema = %MySchema{id: 1, embed: nil}
    changeset =
      put_in(my_schema.__meta__.context, {:invalid, [unique: "my_schema_foo_index"]})
      |> Ecto.Changeset.change(x: "foo")
      |> Ecto.Changeset.put_embed(:embed, embed)
      |> Ecto.Changeset.unique_constraint(:foo)
    assert {:error, changeset} = TestRepo.update(changeset)
    refute changeset.data.embed
    assert changeset.changes.embed
    refute changeset.changes.embed.data.id
    refute changeset.valid?
  end

  test "handles nested embeds on update" do
    embed = %MyEmbed{id: @uuid, x: "xyz"}
    embed_changeset =
      embed
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:sub_embed, %SubEmbed{y: "xyz"})
    changeset =
      %MySchema{id: 1, embed: embed}
      |> Ecto.Changeset.change
      |> Ecto.Changeset.put_embed(:embed, embed_changeset)
    schema = TestRepo.update!(changeset)
    assert schema.embed.sub_embed.y == "xyz"
  end

  ## delete

  test "embeds are not removed on delete" do
    embed = %MyEmbed{id: @uuid, x: "xyz"}

    schema = TestRepo.delete!(%MySchema{id: 1, embed: embed})
    assert schema.embed == embed

    schema = TestRepo.delete!(%MySchema{id: 1, embeds: [embed]})
    assert schema.embeds == [embed]
  end
end
