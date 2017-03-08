require 'rails_helper'

describe API::StancesController do
  let(:user) { create :user }
  let(:another_user) { create :user }
  let(:poll) { create :poll, discussion: discussion }
  let(:poll_option) { create :poll_option, poll: poll }
  let(:old_stance) { create :stance, poll: poll, participant: user, poll_options: [poll_option] }
  let(:discussion) { create :discussion, group: group }
  let(:group) { create :group }
  let(:stance_params) {{
    poll_id: poll.id,
    stance_choices_attributes: [{poll_option_id: poll_option.id}],
    reason: "here is my stance"
  }}

  let(:public_poll) { create :poll, discussion: nil, anyone_can_participate: true }
  let(:public_poll_option) { create :poll_option, poll: public_poll }
  let(:visitor_stance_params) {{
    poll_id: public_poll.id,
    stance_choices_attributes: [{poll_option_id: public_poll_option.id}],
    visitor_attributes: { name: "John Doe", email: "john@doe.ninja" }
  }}

  let(:brainstorm) { create :poll, poll_type: :brainstorm, anyone_can_participate: true, poll_option_names: [] }
  let(:brainstorm_stance_params) {{
    poll_id: brainstorm.id,
    stance_choices_attributes: [
      {poll_option_name: 'to the moon!'},
      {poll_option_name: 'to mars!'}
    ],
    reason: "Here's my thinking"
  }}

  before { group.add_member! user }

  describe 'index' do
    let(:recent_stance) { create :stance, poll: poll, created_at: 1.day.ago, choice: [low_priority_option.name] }
    let(:old_stance) { create :stance, poll: poll, created_at: 5.days.ago, choice: [low_priority_option.name] }
    let(:high_priority_stance) { create :stance, poll: poll, choice: [high_priority_option.name] }
    let(:low_priority_stance) { create :stance, poll: poll, choice: [low_priority_option.name] }
    let(:high_priority_option) { create(:poll_option, poll: poll, priority: 0) }
    let(:low_priority_option) { create(:poll_option, poll: poll, priority: 10) }

    it 'can order by recency asc' do
      sign_in user
      recent_stance; old_stance
      get :index, poll_id: poll.id, order: :newest_first
      expect(response.status).to eq 200
      json = JSON.parse(response.body)

      expect(json['stances'][0]['id']).to eq recent_stance.id
      expect(json['stances'][1]['id']).to eq old_stance.id
    end

    it 'can order by recency desc' do
      sign_in user
      recent_stance; old_stance
      get :index, poll_id: poll.id, order: :oldest_first
      expect(response.status).to eq 200
      json = JSON.parse(response.body)

      expect(json['stances'][0]['id']).to eq old_stance.id
      expect(json['stances'][1]['id']).to eq recent_stance.id
    end

    it 'can order by priority asc' do
      sign_in user
      high_priority_stance; low_priority_stance
      get :index, poll_id: poll.id, order: :priority_first
      expect(response.status).to eq 200
      json = JSON.parse(response.body)

      expect(json['stances'][0]['id']).to eq high_priority_stance.id
      expect(json['stances'][1]['id']).to eq low_priority_stance.id
    end

    it 'can order by priority desc' do
      sign_in user
      high_priority_stance; low_priority_stance
      get :index, poll_id: poll.id, order: :priority_last
      expect(response.status).to eq 200
      json = JSON.parse(response.body)

      expect(json['stances'][0]['id']).to eq low_priority_stance.id
      expect(json['stances'][1]['id']).to eq high_priority_stance.id
    end

    it 'does not allow unauthorized users to get stances' do
      get :index, poll_id: poll.id
      expect(response.status).to eq 403
    end
  end

  describe 'create' do
    it 'creates a new stance' do
      sign_in user
      expect { post :create, stance: stance_params }.to change { Stance.count }.by(1)

      stance = Stance.last
      expect(stance.poll).to eq poll
      expect(stance.poll_options.first).to eq poll_option
      expect(stance.reason).to eq stance_params[:reason]
      expect(stance.latest).to eq true

      expect(response.status).to eq 200
      json = JSON.parse(response.body)
      expect(json['stances'].length).to eq 1
      expect(json['stances'][0]['id']).to eq stance.id
      expect(json['poll_options'].map { |o| o['name'] }).to include poll_option.name
    end

    it 'can create a stance with a new poll option' do
      sign_in user
      stance_choices_count = StanceChoice.count
      poll_options_count = PollOption.count
      expect { post :create, stance: brainstorm_stance_params }.to change { Stance.count }.by(1)
      expect(StanceChoice.count).to eq stance_choices_count + 2
      expect(PollOption.count).to eq poll_options_count + 2

      stance_choice_names = brainstorm_stance_params[:stance_choices_attributes].map { |a| a[:poll_option_name] }
      expect(brainstorm.reload.poll_options.pluck(:name)).to eq stance_choice_names

      stance = Stance.last
      expect(stance.stance_choices.map(&:poll_option).map(&:name)).to eq stance_choice_names
      expect(stance.reason).to eq brainstorm_stance_params[:reason]
    end

    it 'can create a stance with a visitor' do
      expect { post :create, stance: visitor_stance_params }.to change { Stance.count }.by(1)

      stance = Stance.last
      expect(stance.participant.name).to  eq visitor_stance_params[:visitor_attributes][:name]
      expect(stance.participant.email).to eq visitor_stance_params[:visitor_attributes][:email]

      expect(response.status).to eq 200
      json = JSON.parse(response.body)
      names  = json['visitors'].map { |u| u['name'] }
      emails = json['visitors'].map { |u| u['email'] }

      expect(names).to  include visitor_stance_params[:visitor_attributes][:name]
      expect(emails).to include visitor_stance_params[:visitor_attributes][:email]
    end

    describe 'visitor token' do
      it 'sets a visitor cookie if the actor is a visitor' do
        expect { post :create, stance: visitor_stance_params }.to change { Visitor.count }.by(1)
        expect(cookies[:participation_token]).to eq Visitor.last.participation_token
      end

      it 'does not set a visitor cookie for logged in users' do
        sign_in user
        expect { post :create, stance: stance_params }.to_not change { Visitor.count }
        expect(cookies[:participation_token]).to be_nil
      end

      it 'resets the cookie if it exists already as a visitor' do
        cookies[:participation_token] = "abcd"
        post :create, stance: visitor_stance_params
        expect(cookies[:participation_token]).to eq Visitor.last.participation_token
      end

      it 'resets to the cookie if it exists already as a signed in user' do
        sign_in user
        cookies[:participation_token] = "abcd"
        post :create, stance: stance_params
        expect(cookies[:participation_token]).to be_nil
      end

      it 'does not set participation token when the create fails for signed in user' do
        cookies[:participation_token] = "abcd"
        visitor_stance_params[:stance_choices_attributes] = []
        post :create, visitor_stance_params
        expect(response.status).to eq 400
        expect(cookies[:participation_token]).to eq "abcd"
      end

      it 'does not set participation token when the create fails for signed in user' do
        sign_in user
        cookies[:participation_token] = "abcd"
        stance_params[:stance_choices_attributes] = []
        post :create, stance_params
        expect(response.status).to eq 400
        expect(cookies[:participation_token]).to eq "abcd"
      end
    end

    it 'does not create a stance with an incomplete visitor' do
      visitor_stance_params[:visitor_attributes] = {}
      expect { post :create, stance: visitor_stance_params }.to_not change { Stance.count }
      expect(response.status).to eq 422

      json = JSON.parse(response.body)
      expect(json['errors']['participant_name']).to be_present
    end

    it 'does not allow unauthorized visitors to create stances' do
      visitor_stance_params[:poll_id] = poll.id
      expect { post :create, stance: visitor_stance_params }.to_not change { Stance.count }
      expect(response.status).to eq 403
    end

    it 'overwrites existing stances' do
      sign_in user
      old_stance
      expect { post :create, stance: stance_params }.to change { Stance.count }.by(1)
      expect(response.status).to eq 200
      expect(old_stance.reload.latest).to eq false
    end

    it 'does not allow unauthorized visitors to create stances' do
      expect { post :create, stance: stance_params }.to_not change { Stance.count }
      expect(response.status).to eq 403
    end

    it 'does not allow non members to create stances' do
      sign_in another_user
      expect { post :create, stance: stance_params }.to_not change { Stance.count }
      expect(response.status).to eq 403
    end

    it 'does not allow creating an invalid stance' do
      sign_in user
      stance_params[:stance_choices_attributes] = []
      expect { post :create, stance: stance_params }.to_not change { Stance.count }
      expect(response.status).to eq 422
    end
  end
end
