# frozen_string_literal: true

# Backport of Rails fix for GHSA-76r7-hhxj-r776 (CVE-2025-55193)
# Upstream commit: https://github.com/rails/rails/commit/3beef2005a1cbb336af63d77be157e43440d7697
# Strategy: wrap and re-raise with upstream-style message using .inspect.

ActiveSupport.on_load(:active_record) do
    # Relation/Finder path
    ActiveRecord::FinderMethods.module_eval do
      alias_method :__orig_raise_record_not_found_exception!, :raise_record_not_found_exception!

      def raise_record_not_found_exception!(*args)
        __orig_raise_record_not_found_exception!(*args)
      rescue ActiveRecord::RecordNotFound
        klass_name = respond_to?(:klass) && klass ? klass.name : "Record"

        key =
          if args.length >= 4
            args[3]
          elsif respond_to?(:primary_key)
            primary_key
          else
            "id"
          end

        ids       = args[0]
        inspected = Array(ids).map(&:inspect)

        msg =
          if ids.is_a?(Array)
            "Couldn't find #{klass_name} with '#{key}' in #{inspected.join(', ')}"
          else
            "Couldn't find #{klass_name} with '#{key}'=#{inspected.first}"
          end

        raise ActiveRecord::RecordNotFound, msg
      end
    end

    # Model.find path
    ActiveRecord::Base.singleton_class.class_eval do
      alias_method :__orig_find, :find

      def find(*ids)
        __orig_find(*ids)
      rescue ActiveRecord::RecordNotFound
        key       = primary_key
        flat_ids  = (ids.length == 1 && ids.first.is_a?(Array)) ? ids.first : ids
        inspected = Array(flat_ids).map(&:inspect)

        msg =
          if flat_ids.is_a?(Array) && flat_ids.length > 1
            "Couldn't find #{name} with '#{key}' in #{inspected.join(', ')}"
          else
            "Couldn't find #{name} with '#{key}'=#{inspected.first}"
          end

        raise ActiveRecord::RecordNotFound, msg
      end
    end
  end
