angular.module('loomioApp').directive 'installSlackDecideForm', (Session, Records, ModalService, PollCommonStartModal) ->
  templateUrl: 'generated/components/install_slack/decide_form/install_slack_decide_form.html'
  controller: ($scope) ->
    $scope.submit = ->
      ModalService.open PollCommonStartModal, poll: -> Records.polls.build(groupId: Session.currentGroupId)

    $scope.group = ->
      Session.currentGroup
