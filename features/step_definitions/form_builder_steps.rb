When /^I visit the form builder admin page$/ do
  visit noodall_admin_forms_path
end

Then /^I should see a form with at least the following fields:$/ do |table|
  table.rows.each do |row|
    page.should have_selector("input[value='#{row[0]}']")
  end
end

When /^I fill the following fields:$/ do |table|
  table.rows.each do |row|
    @new_form_name = row[1] if @new_form_name.nil?
    fill_in row[0], :with => row[1]
  end
end

When /^I add the fields I want on the form$/ do
# Some selenium dodads here

#  5.times do |i|
#    #get index of new fieldset
#    index = 1
#    response.should have_selector('#form-fields fieldset') do |fieldset|
#      index += 1
#    end
#    click_link_within 'div#main-form', 'Add'
#    save_and_open_page
#
#    within "fieldset#field-#{index}" do |fieldset|
#      fieldset.fill_in 'Name', :with => "Field #{i}"
#    end
#  end
end

Then /^I should see the new form in the Form List$/ do
  page.should have_content(@new_form_name)
end

Given /^I am creating a form$/ do
  visit new_admin_form_path
end

Then /^I should see a new field with the options "([^\"]*)"$/ do |arg1|
  #get index of new fieldset
  index = 0
  page.should have_selector('#form-fields fieldset') do |fieldset|
    index += 1
  end

  page.should have_selector("fieldset#field-#{index}")
end

Given /^a form exists that has had many responses$/ do
  form = Factory(:form)

  responses = []
  9.times do |i|
    responses << Factory(:response)
  end
  form.responses = responses
end

When /^I click "([^\"]*)" on the forms row in the Form List$/ do |arg1|
  within('#content-table table tbody tr:first-child') do |form_row|
    form_row.click_link arg1
  end
end

Then /^I should receive a CSV file containing all the responses to that form$/ do
  assert page.sending_file?
end


Given /^forms have been created with the form builder$/ do
  5.times do
    Factory(:form)
  end
end

Then /^I should see a form select element containing the exisitng forms$/ do
  Form.all.each do |form|
    page.should have_selector("select#node_wide_slot_0_form_id option:contains('#{form.title}')")
  end
end

When /^I select a form$/ do
  @_form = Form.first
  select @_form.title, :from => 'Form'
end

Then /^I should see the form I selected$/ do
  @_form.fields.each do |field|
    page.should have_selector("label[for=form_response_#{field.underscored_name}]")
  end
end

Given /^a form exists$/ do
  Factory(:form)
end

Given /^content exists with a form added via the contact module$/ do
  @_node = Factory(:page_a)
  @_form = Factory(:form)
  @_node.wide_slot_0 = Factory(:contact_form, :form_id => @_form.id)
  @_node.save
end

When /^a website visitor visits the content$/ do
  visit node_path(@_node)
end

Then /^they should see the form$/ do
  Then %{I should see the form I selected}
end

When /^they fill in and submit the form$/ do
  @_form = Form.find(@_node.wide_slot_0.form_id)
  @_form.fields.each do |field|
    case field.class.name
    when 'TextField'
      if field.name == 'Email'
        fill_in "form_response[#{field.underscored_name}]", :with => 'hello@wearebeef.co.uk'
      else
        fill_in "form_response[#{field.underscored_name}]", :with => 'Weopunggggggggst'
      end
    end
  end

  When %{they submit the form}
end

Then /^the email address of the form should receive an email detailing the information submitted$/ do
  Then %{"#{@_form.email}" should receive an email}
  @_form.fields do |field|
    Then %{they should see "#{field.name}:" in the email body}
  end
end

Then /^they should receive an email confirming the request has been sent$/ do
  Then %{"hello@wearebeef.co.uk" should receive an email}
  @_form.fields do |field|
    Then %{they should see "#{field.name}:" in the email body}
  end
end

Then /^the response should be stored in the database along with the time submitted, IP address, and page it was submitted from$/ do
  @_form.reload
  @response = @_form.responses.last

  @response.created_at.should_not be nil
  @response.ip.should == '127.0.0.1'
  @response.referrer.should == node_path(@_node)
end

Then /^it should be checked by a spam filter$/ do
  #err
end

Then /^it should be rejected if the spam filter deems the response to be spam$/ do
  within('form #errorExplanation') do
    page.should have_content('spam')
  end
end

Then /^the website visitor should see an spam message$/ do
  Then %{it should be rejected if the spam filter deems the response to be spam}
end

Then /^it should be checked against the validation speficied in the form builder$/ do
  @_form.required_fields.each do |field|
    within('#errorExplanation') do |error_message|
      page.should have_content(field.name)
    end
  end
end

Then /^it should be rejected if the the response does not meet the validation$/ do
  Then %{it should be checked against the validation speficied in the form builder}
end

Then /^the website visitor should see an error message$/ do
    page.should have_selector('form #errorExplanation')
end

Given /^the spam filter is activated$/ do
  class DummyDefensio
    def post_document(*args)
      [200, {:spaminess => 1}]
    end
  end

  Defensio.should_receive(:new).and_return(DummyDefensio.new())
end

When /^a website visitor fills in and submits a form$/ do
  When %{they fill in and submit the form}
end

When /^they submit the form$/ do
  click_button 'Send'
end