# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NamespacePolicy do
  let(:owner) { build_stubbed(:user) }
  let(:namespace) { build_stubbed(:namespace, owner: owner) }
  let(:admin) { build_stubbed(:admin) }
  let(:owner_permissions) { [:create_projects, :admin_namespace, :read_namespace] }

  subject { described_class.new(current_user, namespace) }

  context 'auditor' do
    let(:current_user) { build_stubbed(:user, :auditor) }

    context 'owner' do
      let(:namespace) { build_stubbed(:namespace, owner: current_user) }

      it { is_expected.to be_allowed(*owner_permissions) }
    end

    context 'non-owner' do
      it { is_expected.to be_disallowed(*owner_permissions) }
    end
  end

  context ':over_storage_limit' do
    let(:current_user) { owner }

    before do
      allow(namespace).to receive(:over_storage_limit?).and_return(over_storage_limit)
    end

    context 'when the namespace has exceeded its storage limit' do
      let(:over_storage_limit) { true }

      it { is_expected.to(be_disallowed(:create_projects)) }
    end

    context 'when the namespace has not exceeded its storage limit' do
      let(:over_storage_limit) { false }

      it { is_expected.to(be_allowed(:create_projects)) }
    end
  end

  context ':admin_compliance_framework' do
    shared_examples 'permitted' do
      it { is_expected.to(be_allowed(:admin_compliance_framework)) }
    end

    shared_examples 'not permitted' do
      it { is_expected.to(be_disallowed(:admin_compliance_framework)) }
    end

    context 'when feature is licensed' do
      before do
        stub_licensed_features(custom_compliance_frameworks: true)
      end

      context 'when user is admin', :enable_admin_mode do
        let(:current_user) { admin }

        it_behaves_like 'permitted'
      end

      context 'when user is owner' do
        let(:current_user) { owner }

        it_behaves_like 'permitted'
      end
    end

    context 'when feature is not licensed' do
      before do
        stub_licensed_features(custom_compliance_frameworks: false)
      end

      context 'when user is admin', :enable_admin_mode do
        let(:current_user) { admin }

        it_behaves_like 'not permitted'
      end

      context 'when user is owner' do
        let(:current_user) { owner }

        it_behaves_like 'not permitted'
      end
    end
  end

  it_behaves_like 'update namespace limit policy'
end
