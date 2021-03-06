module Validations # :nodoc:
  module ValidatesUniquenessOfWithoutDeleted # :nodoc:

      #Extends the validates_uniqueness_of method to accept a :without_deleted parameter
      #which allows you to ignore 'deleted' records in your validations
      def validates_uniqueness_of_without_deleted(*attr_names)
        configuration = { :message => ActiveRecord::Errors.default_error_messages[:taken] }
        configuration.update(attr_names.extract_options!)

        validates_each(attr_names,configuration) do |record, attr_name, value|
          # The check for an existing value should be run from a class that
          # isn't abstract. This means working down from the current class
          # (self), to the first non-abstract class. Since classes don't know
          # their subclasses, we have to build the hierarchy between self and
          # the record's class.
          class_hierarchy = [record.class]
          while class_hierarchy.first != self
            class_hierarchy.insert(0, class_hierarchy.first.superclass)
          end

          # Now we can work our way down the tree to the first non-abstract
          # class (which has a database table to query from).
          finder_class = class_hierarchy.detect { |klass| !klass.abstract_class? }

          if value.nil? || (configuration[:case_sensitive] || !finder_class.columns_hash[attr_name.to_s].text?)
            condition_sql = "#{record.class.quoted_table_name}.#{attr_name} #{attribute_condition(value)}"
            condition_params = [value]
          else
            # sqlite has case sensitive SELECT query, while MySQL/Postgresql don't.
            # Hence, this is needed only for sqlite.
            condition_sql = "LOWER(#{record.class.quoted_table_name}.#{attr_name}) #{attribute_condition(value)}"
            condition_params = [value.downcase]
          end

          if scope = configuration[:scope]
            Array(scope).map do |scope_item|
              scope_value = record.send(scope_item)
              condition_sql << " AND #{record.class.quoted_table_name}.#{scope_item} #{attribute_condition(scope_value)}"
              condition_params << scope_value
            end
          end

          unless record.new_record?
            condition_sql << " AND #{record.class.quoted_table_name}.#{record.class.primary_key} <> ?"
            condition_params << record.send(:id)
          end

          if with_deleted = configuration[:without_deleted]
            condition_sql << " AND #{record.class.quoted_table_name}.deleted_at is NULL"
          end

          results = finder_class.with_exclusive_scope do
            connection.select_all(
              construct_finder_sql(
                :select     => attr_name,
                :from       => finder_class.quoted_table_name,
                :conditions => [condition_sql, *condition_params]
              )
            )
          end

          unless results.length.zero?
            found = true

            # As MySQL/Postgres don't have case sensitive SELECT queries, we try to find duplicate
            # column in ruby when case sensitive option
            if configuration[:case_sensitive] && finder_class.columns_hash[attr_name.to_s].text?
              found = results.any? { |a| a[attr_name.to_s] == value }
            end

            record.errors.add(attr_name, configuration[:message]) if found
          end
        end
      end

  end
end