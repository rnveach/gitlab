import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import * as types from './mutation_types';
import { transformRawStages } from '../utils';

export default {
  [types.SET_FEATURE_FLAGS](state, featureFlags) {
    state.featureFlags = featureFlags;
  },
  [types.SET_SELECTED_GROUP](state, group) {
    state.selectedGroup = convertObjectPropsToCamelCase(group, { deep: true });
    state.selectedProjects = [];
  },
  [types.SET_SELECTED_PROJECTS](state, projects) {
    state.selectedProjects = projects;
  },
  [types.SET_SELECTED_STAGE](state, rawData) {
    state.selectedStage = convertObjectPropsToCamelCase(rawData);
  },
  [types.SET_DATE_RANGE](state, { startDate, endDate }) {
    state.startDate = startDate;
    state.endDate = endDate;
  },
  [types.REQUEST_CYCLE_ANALYTICS_DATA](state) {
    state.isLoading = true;
  },
  [types.RECEIVE_CYCLE_ANALYTICS_DATA_SUCCESS](state) {
    state.errorCode = null;
    state.isLoading = false;
  },
  [types.RECEIVE_CYCLE_ANALYTICS_DATA_ERROR](state, errCode) {
    state.errorCode = errCode;
    state.isLoading = false;
  },
  [types.REQUEST_STAGE_MEDIANS](state) {
    state.medians = {};
  },
  [types.RECEIVE_STAGE_MEDIANS_SUCCESS](state, medians = []) {
    state.medians = medians.reduce(
      (acc, { id, value }) => ({
        ...acc,
        [id]: value,
      }),
      {},
    );
  },
  [types.RECEIVE_STAGE_MEDIANS_ERROR](state) {
    state.medians = {};
  },
  [types.REQUEST_GROUP_STAGES](state) {
    state.stages = [];
  },
  [types.RECEIVE_GROUP_STAGES_ERROR](state) {
    state.stages = [];
  },
  [types.RECEIVE_GROUP_STAGES_SUCCESS](state, stages) {
    state.stages = transformRawStages(stages);
  },
  [types.REQUEST_UPDATE_STAGE](state) {
    state.isLoading = true;
  },
  [types.RECEIVE_UPDATE_STAGE_SUCCESS](state) {
    state.isLoading = false;
  },
  [types.RECEIVE_UPDATE_STAGE_ERROR](state) {
    state.isLoading = false;
  },
  [types.REQUEST_REMOVE_STAGE](state) {
    state.isLoading = true;
  },
  [types.RECEIVE_REMOVE_STAGE_RESPONSE](state) {
    state.isLoading = false;
  },
  [types.INITIALIZE_CYCLE_ANALYTICS](
    state,
    {
      group: selectedGroup = null,
      createdAfter: startDate = null,
      createdBefore: endDate = null,
      selectedProjects = [],
    } = {},
  ) {
    state.isLoading = true;
    state.selectedGroup = selectedGroup;
    state.selectedProjects = selectedProjects;
    state.startDate = startDate;
    state.endDate = endDate;
  },
  [types.INITIALIZE_CYCLE_ANALYTICS_SUCCESS](state) {
    state.isLoading = false;
  },
  [types.REQUEST_REORDER_STAGE](state) {
    state.isSavingStageOrder = true;
    state.errorSavingStageOrder = false;
  },
  [types.RECEIVE_REORDER_STAGE_SUCCESS](state) {
    state.isSavingStageOrder = false;
    state.errorSavingStageOrder = false;
  },
  [types.RECEIVE_REORDER_STAGE_ERROR](state) {
    state.isSavingStageOrder = false;
    state.errorSavingStageOrder = true;
  },
};
