# frozen_string_literal: true

# To support GlobalID arguments that present a model with its old "deprecated" name
# we alter GlobalID so it will correctly find the record with its new model name.
module Gitlab
  module Patch
    module GlobalID
      def initialize(gid, options = {})
        super(gid, options).tap do |uri|
          if deprecation = Gitlab::GlobalId::Deprecations.deprecation_for(model_name)
            uri.instance_variable_set(:@model_name, deprecation.new_model_name)
          end
        end
      end
    end
  end
end
