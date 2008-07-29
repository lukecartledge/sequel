require 'win32ole'

module Sequel
  # The ADO adapter provides connectivity to ADO databases in Windows. ADO
  # databases can be opened using a URL with the ado schema:
  #
  #   DB = Sequel.open('ado://mydb')
  # 
  # or using the Sequel.ado method:
  #
  #   DB = Sequel.ado('mydb')
  #
  module ADO
    class Database < Sequel::Database
      set_adapter_scheme :ado

      def connect
        @opts[:driver] ||= 'SQL Server'
        case @opts[:driver]
        when 'SQL Server'
          require 'sequel_core/adapters/shared/mssql'
          extend Sequel::MSSQL::DatabaseMethods
        end
        s = "driver=#{@opts[:driver]};server=#{@opts[:host]};database=#{@opts[:database]}#{";uid=#{@opts[:user]};pwd=#{@opts[:password]}" if @opts[:user]}"
        handle = WIN32OLE.new('ADODB.Connection')
        handle.Open(s)
        handle
      end
      
      def disconnect
        @pool.disconnect {|conn| conn.Close}
      end
    
      def dataset(opts = nil)
        ADO::Dataset.new(self, opts)
      end
    
      def execute(sql)
        log_info(sql)
        @pool.hold {|conn| conn.Execute(sql)}
      end
      alias_method :do, :execute
    end
    
    class Dataset < Sequel::Dataset
      def literal(v)
        case v
        when Time
          literal(v.iso8601)
        when Date, DateTime
          literal(v.to_s)
        else
          super
        end
      end

      def fetch_rows(sql, &block)
        @db.synchronize do
          s = @db.execute sql
          
          @columns = s.Fields.extend(Enumerable).map do |column|
            name = column.Name.empty? ? '(no column name)' : column.Name
            name.to_sym
          end
          
          unless s.eof
            s.moveFirst
            s.getRows.transpose.each {|r| yield hash_row(r)}
          end
        end
        self
      end
      
      def hash_row(row)
        @columns.inject({}) do |m, c|
          m[c] = row.shift
          m
        end
      end
    end
  end
end
