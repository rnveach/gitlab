import Vue from 'vue';
import Vuex from 'vuex';
import NewUserList from 'ee/user_lists/components/new_user_list.vue';
import createStore from 'ee/user_lists/store/new';

Vue.use(Vuex);

document.addEventListener('DOMContentLoaded', () => {
  const el = document.getElementById('js-new-user-list');
  const { userListsDocsPath, featureFlagsPath } = el.dataset;
  return new Vue({
    el,
    store: createStore(el.dataset),
    provide: {
      userListsDocsPath,
      featureFlagsPath,
    },
    render(h) {
      return h(NewUserList);
    },
  });
});
