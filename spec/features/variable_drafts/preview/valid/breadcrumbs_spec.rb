require 'rails_helper'

describe 'Variable drafts valid breadcrumbs' do
  before do
    login
    @draft = create(:full_variable_draft, user: User.where(urs_uid: 'testuser').first)
    visit variable_draft_path(@draft)
  end

  context 'when viewing the breadcrumbs' do
    it 'displays the name' do
      within '.eui-breadcrumbs' do
        expect(page).to have_content('Variable Drafts')
        expect(page).to have_content(@draft.draft['Name'])
      end
    end
  end
end
