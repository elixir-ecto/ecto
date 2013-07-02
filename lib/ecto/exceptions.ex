defexception Ecto.InvalidQuery, reason: nil, type: nil, query: nil, file: nil, line: nil do
  def message(e) do
    if e.type && e.query && e.file && e.line do
      "the query #{e.type}: #{Macro.to_string(e.query)} at #{e.file}:#{e.line} " <>
      "is invalid: #{e.reason}"
    else
      e.reason
    end
  end
end

defexception Ecto.InvalidURL, [url: nil, reason: nil] do
  def message(Ecto.InvalidURL[url: url, reason: reason]) do
    "invalid url #{url}: #{reason}"
  end
end
