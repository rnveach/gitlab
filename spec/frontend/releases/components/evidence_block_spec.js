import { mount } from '@vue/test-utils';
import { GlLink } from '@gitlab/ui';
import { truncateSha } from '~/lib/utils/text_utility';
import Icon from '~/vue_shared/components/icon.vue';
import { release as originalRelease } from '../mock_data';
import EvidenceBlock from '~/releases/components/evidence_block.vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';

describe('Evidence Block', () => {
  let wrapper;
  let release;

  const factory = (options = {}) => {
    wrapper = mount(EvidenceBlock, {
      ...options,
    });
  };

  beforeEach(() => {
    release = convertObjectPropsToCamelCase(originalRelease, { deep: true });

    factory({
      propsData: {
        release,
      },
    });
  });

  afterEach(() => {
    wrapper.destroy();
  });

  it('renders the evidence icon', () => {
    expect(wrapper.find(Icon).props('name')).toBe('review-list');
  });

  it('renders the title for the dowload link', () => {
    expect(wrapper.find(GlLink).text()).toBe('v1.1.2-evidences-1.json');
  });

  it('renders the correct hover text for the download', () => {
    expect(wrapper.find(GlLink).attributes('title')).toBe('Download evidence JSON');
  });

  it('renders the correct file link for download', () => {
    expect(wrapper.find(GlLink).attributes().download).toBe('v1.1.2-evidences-1.json');
  });

  describe('sha text', () => {
    it('renders the short sha initially', () => {
      expect(wrapper.find('.js-short').text()).toBe(truncateSha(release.evidences[0].sha));
    });

    it('renders the long sha after expansion', () => {
      wrapper.find('.js-text-expander-prepend').trigger('click');

      return wrapper.vm.$nextTick().then(() => {
        expect(wrapper.find('.js-expanded').text()).toBe(release.evidences[0].sha);
      });
    });
  });

  describe('copy to clipboard button', () => {
    it('renders button', () => {
      expect(wrapper.find(ClipboardButton).exists()).toBe(true);
    });

    it('renders the correct hover text', () => {
      expect(wrapper.find(ClipboardButton).attributes('title')).toBe('Copy commit SHA');
    });

    it('copies the sha', () => {
      expect(wrapper.find(ClipboardButton).attributes('data-clipboard-text')).toBe(
        release.evidences[0].sha,
      );
    });
  });
});
