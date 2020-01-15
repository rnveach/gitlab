# frozen_string_literal: true

require 'spec_helper'

describe Namespace do
  shared_examples 'plan helper' do |namespace_plan|
    let(:namespace) { create(:namespace, plan: "#{plan_name}_plan") }

    subject { namespace.public_send("#{namespace_plan}_plan?") }

    context "for a #{namespace_plan} plan" do
      let(:plan_name) { namespace_plan }

      it { is_expected.to eq(true) }
    end

    context "for a plan that isn't #{namespace_plan}" do
      where(plan_name: described_class::PLANS - [namespace_plan])

      with_them do
        it { is_expected.to eq(false) }
      end
    end
  end

  described_class::PLANS.each do |namespace_plan|
    describe "#{namespace_plan}_plan?" do
      it_behaves_like 'plan helper', namespace_plan
    end
  end

  describe '#use_elasticsearch?' do
    let(:namespace) { create :namespace }

    it 'returns false if elasticsearch indexing is disabled' do
      stub_ee_application_setting(elasticsearch_indexing: false)

      expect(namespace.use_elasticsearch?).to eq(false)
    end

    it 'returns true if elasticsearch indexing enabled but limited indexing disabled' do
      stub_ee_application_setting(elasticsearch_indexing: true, elasticsearch_limit_indexing: false)

      expect(namespace.use_elasticsearch?).to eq(true)
    end

    it 'returns true if it is enabled specifically' do
      stub_ee_application_setting(elasticsearch_indexing: true, elasticsearch_limit_indexing: true)

      expect(namespace.use_elasticsearch?).to eq(false)

      create :elasticsearch_indexed_namespace, namespace: namespace

      expect(namespace.use_elasticsearch?).to eq(true)
    end
  end

  describe '#trial_active?' do
    subject { create(:namespace) }

    where(:trial, :trial_ends_on, :return_result) do
      now = Date.new(2000, 5, 5)

      [
        [nil,   now + 1.day, false],
        [nil,   now,         false],
        [nil,   now - 1.day, false],
        [true,  now + 1.day, true],
        [true,  now,         true],
        [true,  now - 1.day, false],
        [false, now + 1.day, false],
        [false, now,         false],
        [false, now - 1.day, false],
      ]
    end

    it 'returns false if no GitlabSubscription' do
      expect(subject.trial_active?).to eq(false)
    end

    with_them do
      before do
        create(:gitlab_subscription, namespace_id: subject.id, trial: trial, trial_ends_on: trial_ends_on)
      end

      it 'returns true if GitlabSubscription is on trial' do
        Timecop.freeze(Date.new(2000, 5, 5)) do
          expect(subject.trial_active?).to eq(return_result)
        end
      end
    end
  end
end
