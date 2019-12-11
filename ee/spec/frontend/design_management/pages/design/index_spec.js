import { shallowMount } from '@vue/test-utils';
import { ApolloMutation } from 'vue-apollo';
import DesignIndex from 'ee/design_management/pages/design/index.vue';
import DesignDiscussion from 'ee/design_management/components/design_notes/design_discussion.vue';
import DesignReplyForm from 'ee/design_management/components/design_notes/design_reply_form.vue';
import createImageDiffNoteMutation from 'ee/design_management/graphql/mutations/createImageDiffNote.mutation.graphql';
import * as utils from 'ee/design_management/utils/design_management_utils';
import design from '../../mock_data/design';

jest.mock('mousetrap', () => ({
  bind: jest.fn(),
  unbind: jest.fn(),
}));

describe('Design management design index page', () => {
  let wrapper;
  const newComment = 'new comment';
  const annotationCoordinates = {
    x: 10,
    y: 10,
    width: 100,
    height: 100,
  };
  const mutationVariables = {
    mutation: createImageDiffNoteMutation,
    update: expect.anything(),
    variables: {
      input: {
        body: newComment,
        noteableId: design.id,
        position: {
          headSha: 'headSha',
          baseSha: 'baseSha',
          startSha: 'startSha',
          paths: {
            newPath: 'full-design-path',
          },
          ...annotationCoordinates,
        },
      },
    },
  };
  const mutate = jest.fn(() => Promise.resolve());

  const findDiscussions = () => wrapper.findAll(DesignDiscussion);
  const findDiscussionForm = () => wrapper.find(DesignReplyForm);

  function createComponent(loading = false) {
    const $apollo = {
      queries: {
        design: {
          loading,
        },
      },
      mutate,
    };

    wrapper = shallowMount(DesignIndex, {
      sync: false,
      propsData: { id: '1' },
      mocks: { $apollo },
      stubs: {
        ApolloMutation,
      },
    });

    wrapper.setData({
      issueIid: '1',
    });
  }

  function setDesign() {
    createComponent(true);
    wrapper.vm.$apollo.queries.design.loading = false;
  }

  afterEach(() => {
    wrapper.destroy();
  });

  it('sets loading state', () => {
    createComponent(true);

    expect(wrapper.element).toMatchSnapshot();
  });

  it('renders design index', () => {
    setDesign();

    wrapper.setData({
      design,
    });

    expect(wrapper.element).toMatchSnapshot();
  });

  describe('when has no discussions', () => {
    beforeEach(() => {
      setDesign();

      wrapper.setData({
        design: {
          ...design,
          discussions: {
            edges: [],
          },
        },
      });
    });

    it('does not render discussions', () => {
      expect(findDiscussions().exists()).toBe(false);
    });

    it('renders a message about possibility to create a new discussion', () => {
      expect(wrapper.find('.new-discussion-disclaimer').exists()).toBe(true);
    });
  });

  describe('when has discussions', () => {
    beforeEach(() => {
      setDesign();

      wrapper.setData({
        design,
      });
    });

    it('renders correct amount of discussions', () => {
      expect(findDiscussions().length).toBe(1);
    });
  });

  it('opens a new discussion form', () => {
    setDesign();

    wrapper.setData({
      design: {
        ...design,
        discussions: {
          edges: [],
        },
      },
    });

    wrapper.vm.openCommentForm({ x: 0, y: 0 });

    return wrapper.vm.$nextTick().then(() => {
      expect(findDiscussionForm().exists()).toBe(true);
    });
  });

  it('sends a mutation on submitting form and closes form', () => {
    setDesign();

    wrapper.setData({
      design: {
        ...design,
        discussions: {
          edges: [],
        },
      },
      annotationCoordinates,
      comment: newComment,
    });

    return wrapper.vm
      .$nextTick()
      .then(() => {
        findDiscussionForm().vm.$emit('submitForm');

        expect(mutate).toHaveBeenCalledWith(mutationVariables);
        return mutate({ variables: mutationVariables });
      })
      .then(() => {
        expect(findDiscussionForm().exists()).toBe(false);
      });
  });

  describe('flash', () => {
    beforeEach(() => {
      setDesign();

      wrapper.setData({
        design: {
          ...design,
          discussions: {
            edges: [],
          },
        },
      });
    });
    it('container is in correct position in DOM', () => {
      wrapper.vm.$nextTick(() => {
        // tests that `design-detail` class exists on Component container,
        // and that the '.flash-container' element exists and is placed correctly
        expect(wrapper.element).toMatchSnapshot();
      });
    });
    it('creates flash on mutation error', () => {
      utils.createDesignDetailFlash = jest.fn();

      try {
        wrapper.vm.onMutationError('test error');
      } catch (e) {
        expect(utils.createDesignDetailFlash).toHaveBeenCalled();
      }
    });
  });
});
