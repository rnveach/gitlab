module QA
  context 'Manage', :smoke do
    describe 'basic user login' do
      it 'user logs in using basic credentials' do
        Runtime::Browser.visit(:gitlab, Page::Main::Login)
        Page::Main::Login.act { sign_in_using_credentials }

        # TODO, since `Signed in successfully` message was removed
        # this is the only way to tell if user is signed in correctly.
        #
        Page::Main::Menu.perform do |menu|
          expect(menu).to have_personal_area
        end
      end
    end
  end
end
