defrecord EMysql.Result, [:command, :columns, :rows, :num_rows]

defrecord EMysql.OkPacket, [:affected_rows, :insert_id, :msg]

defrecord EMysql.Error, [:msg]
