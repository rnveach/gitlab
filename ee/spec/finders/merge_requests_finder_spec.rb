# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequestsFinder do
  describe '#execute' do
    include_context 'MergeRequestsFinder multiple projects with merge requests context'

    it 'ignores filtering by weight' do
      params = { project_id: project1.id, scope: 'authored', state: 'opened', weight: Issue::WEIGHT_ANY }

      merge_requests = described_class.new(user, params).execute

      expect(merge_requests).to contain_exactly(merge_request1)
    end

    context 'merge commit sha' do
      let_it_be(:merged_merge_request) do
        create(:merge_request, :simple, author: user,
               source_project: project4, target_project: project4,
               state: :merged, merge_commit_sha: 'rurebf')
      end

      it 'filters by merge commit sha' do
        merge_requests = described_class.new(
          user,
          merge_commit_sha: merged_merge_request.merge_commit_sha
        ).execute

        expect(merge_requests).to contain_exactly(merged_merge_request)
      end
    end

    context 'filtering by approver' do
      let(:params) { { approver_ids: [user2.id], approver_usernames: [user2.username] } }

      it 'calls the finder method' do
        expect(::MergeRequests::ByApproversFinder).to receive(:new).with([user2.username], [user2.id]).and_call_original
        described_class.new(user, params).execute
      end

      context 'not filter' do
        let(:params) { { not: { approver_ids: [user2.id], approver_usernames: [user2.username] } } }

        it 'calls the finder method' do
          expect(::MergeRequests::ByApproversFinder).to receive(:new).with([user2.username], [user2.id], negated: true).and_call_original
          described_class.new(user, params).execute
        end
      end
    end
  end
end
