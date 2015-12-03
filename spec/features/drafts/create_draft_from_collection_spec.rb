# MMT-26

require 'rails_helper'

describe 'Create new draft from collection', js: true do
  entry_id = 'ACR3L2DM_1'
  entry_title = 'ACRIM III Level 2 Daily Mean Data V001'

  context 'when editing a CMR collection' do
    before do
      login
      fill_in 'entry_id', with: entry_id
      click_on 'Find'

      click_on entry_id

      click_on 'Edit Record'
    end

    it 'displays a confirmation message' do
      expect(page).to have_content('Draft was successfully created')
    end

    it 'creates a new draft' do
      expect(Draft.count).to eq(1)
    end

    it 'saves the native_id from the published collection' do
      draft = Draft.first
      expect(draft.native_id).to eq('collection25')
    end

    it 'displays the draft preview page' do
      expect(page).to have_content('DRAFT RECORD')
      expect(page).to have_content(entry_title)
    end
  end
end
