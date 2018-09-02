# this class is responsible of converting the hash of conditions
# in "where conditions" to generate the sql query
# it consists of a names_cache that helps calculating the next name given to the association
# it tries to reflect the bahavior of ActiveRecord when generating aliases for tables.
module CanCan
  module ModelAdapters
    class ConditionsExtractor
      def initialize(model_class)
        @names_cache = { model_class.table_name => [] }.with_indifferent_access
        @root_model_class = model_class
      end

      def tableize_conditions(conditions, model_class = @root_model_class, nesting_level = 0)
        return conditions unless conditions.is_a? Hash
        conditions.each_with_object({}) do |(key, value), result_hash|
          if value.is_a? Hash
            result_hash.merge!(calculate_result_hash(key, model_class, nesting_level, result_hash, value))
          else
            result_hash[key] = value
          end
          result_hash
        end
      end

      private

      def calculate_result_hash(key, model_class, nesting_level, result_hash, value)
        reflection = model_class.reflect_on_association(key)
        unless reflection
          raise WrongAssociationName, "association #{key} not defined in model #{model_class.name}"
        end
        nested_resulted = calculate_nested(model_class, result_hash, key, value.dup, nesting_level)
        association_class = reflection.klass.name.constantize
        tableize_conditions(nested_resulted, association_class, nesting_level + 1)
      end

      def calculate_nested(model_class, result_hash, relation_name, value, nesting_level)
        value.each_with_object({}) do |(k, v), nested|
          if v.is_a? Hash
            value.delete(k)
            nested[k] = v
          else
            table_alias = generate_table_alias(model_class, relation_name, nesting_level)
            result_hash[table_alias] = value
          end
          nested
        end
      end

      def generate_table_alias(model_class, relation_name, nesting_level)
        table_alias = model_class.reflect_on_association(relation_name).table_name.to_sym

        if alredy_used?(table_alias, relation_name, nesting_level)
          table_alias = "#{relation_name.to_s.pluralize}_#{model_class.table_name}".to_sym

          index = 1
          while alredy_used?(table_alias, relation_name, nesting_level)
            table_alias = "#{table_alias}_#{index += 1}".to_sym
          end
        end
        add_to_cache(table_alias, relation_name, nesting_level)
      end

      def alredy_used?(table_alias, relation_name, nesting_level)
        @names_cache[table_alias].try(:exclude?, "#{relation_name}_#{nesting_level}")
      end

      def add_to_cache(table_alias, relation_name, nesting_level)
        @names_cache[table_alias] ||= []
        @names_cache[table_alias] << "#{relation_name}_#{nesting_level}"
        table_alias
      end
    end
  end
end
