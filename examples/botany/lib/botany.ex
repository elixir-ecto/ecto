defmodule Botany do

  def get_recursive_accessions(top) do
    top = top |> Botany.Repo.preload(:children) |> Botany.Repo.preload(:accessions)
    Enum.reduce(Enum.map(top.children, &(Botany.get_recursive_accessions(&1))), top.accessions, fn x, acc -> x ++ acc end)
  end

  def get_recursive_accessions_by_name(top_name) do
    import Ecto.Query
    top = from(t in Botany.Taxon, where: t.epithet==^top_name)|> Botany.Repo.one
    Botany.get_recursive_accessions(top)
  end
end
