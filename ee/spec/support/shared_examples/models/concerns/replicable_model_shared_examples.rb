# frozen_string_literal: true

# Required let variables:
#
# - model_record: A valid, unpersisted instance of the model class
#
# We do not use `described_class` here, so we can include this in replicator
# strategy shared examples instead of in *every* model spec.
RSpec.shared_examples 'a replicable model' do
  include EE::GeoHelpers

  describe '#replicator' do
    it 'is defined and does not raise error' do
      expect(model_record.replicator).to be_a(Gitlab::Geo::Replicator)
    end
  end

  it 'invokes replicator.handle_after_create_commit on create' do
    expect(model_record.replicator).to receive(:handle_after_create_commit)

    model_record.save!
  end
end
