require 'test_helper'

#  was the web request successful?
#  was the user redirected to the right page?
#  was the user successfully authenticated?
#  was the correct object stored in the response?
#  was the appropriate message delivered in the json payload?

class DeviseTokenAuth::PasswordsControllerTest < ActionController::TestCase
  describe DeviseTokenAuth::PasswordsController do
    describe "Password reset" do
      before do
        @resource = users(:confirmed_email_user)
        @redirect_url = 'http://ng-token-auth.dev'
      end

      describe 'not email should return 401' do
        before do
          @auth_headers = @resource.create_new_auth_token
          @new_password = Faker::Internet.password

          xhr :post, :create, {
            redirect_url: @redirect_url
          }
          @data = JSON.parse(response.body)
        end

        test 'response should fail' do
          assert_equal 401, response.status
        end
        test 'error message should be returned' do
          assert @data["errors"]
          assert_equal @data["errors"], [I18n.t("devise_token_auth.passwords.missing_email")]
        end
      end
      describe 'not redirect_url should return 401' do
        before do
          @auth_headers = @resource.create_new_auth_token
          @new_password = Faker::Internet.password

          xhr :post, :create, {
            email:        'chester@cheet.ah',
          }
          @data = JSON.parse(response.body)
        end

        test 'response should fail' do
          assert_equal 401, response.status
        end
        test 'error message should be returned' do
          assert @data["errors"]
          assert_equal @data["errors"], [I18n.t("devise_token_auth.passwords.missing_redirect_url")]
        end
      end

      describe 'request password reset' do
        describe 'unknown user should return 404' do
          before do
            xhr :post, :create, {
              email:        'chester@cheet.ah',
              redirect_url: @redirect_url
            }
            @data = JSON.parse(response.body)
          end
          test 'unknown user should return 404' do
            assert_equal 404, response.status
          end

          test 'errors should be returned' do
            assert @data["errors"]
            assert_equal @data["errors"], [I18n.t("devise_token_auth.passwords.user_not_found", email: 'chester@cheet.ah')]
          end
        end


        describe 'case-sensitive email' do
          before do
            xhr :post, :create, {
              email:        @resource.email,
              redirect_url: @redirect_url
            }

            @mail = ActionMailer::Base.deliveries.last
            @resource.reload
            @data = JSON.parse(response.body)

            @mail_config_name  = CGI.unescape(@mail.body.match(/config=([^&]*)&/)[1])
            @mail_redirect_url = CGI.unescape(@mail.body.match(/redirect_url=([^&]*)&/)[1])
            @mail_reset_token  = @mail.body.match(/reset_password_token=(.*)\"/)[1]
          end

          test 'response should return success status' do
            assert_equal 200, response.status
          end

          test 'response should contains message' do
            assert_equal @data["message"], I18n.t("devise_token_auth.passwords.sended", email: @resource.email)
          end

          test 'action should send an email' do
            assert @mail
          end

          test 'the email should be addressed to the user' do
            assert_equal @mail.to.first, @resource.email
          end

          test 'the email body should contain a link with redirect url as a query param' do
            assert_equal @redirect_url, @mail_redirect_url
          end

          test 'the client config name should fall back to "default"' do
            assert_equal 'default', @mail_config_name
          end

          test 'the email body should contain a link with reset token as a query param' do
            user = User.reset_password_by_token({
              reset_password_token: @mail_reset_token
            })

            assert_equal user.id, @resource.id
          end

          describe 'password reset link failure' do
            test 'respone should return 404' do
              xhr :get, :edit, {
                  reset_password_token: 'bogus',
                  redirect_url: @mail_redirect_url
              }

              assert_equal 404, response.status
            end
          end

          describe 'password reset link success' do
            before do
              xhr :get, :edit, {
                reset_password_token: @mail_reset_token,
                redirect_url: @mail_redirect_url
              }

              @resource.reload

              raw_qs = response.location.split('?')[1]
              @qs = Rack::Utils.parse_nested_query(raw_qs)

              @client_id      = @qs["client_id"]
              @expiry         = @qs["expiry"]
              @reset_password = @qs["reset_password"]
              @token          = @qs["token"]
              @uid            = @qs["uid"]
            end

            test 'respones should have success redirect status' do
              assert_equal 302, response.status
            end

            test 'response should contain auth params' do
              assert @client_id
              assert @expiry
              assert @reset_password
              assert @token
              assert @uid
            end

            test 'response auth params should be valid' do
              assert @resource.valid_token?(@token, @client_id)
            end
          end

        end

        describe 'case-insensitive email' do
          before do
            @resource_class = User
            @request_params = {
              email:        @resource.email.upcase,
              redirect_url: @redirect_url
            }
          end

          test 'response should return success status if configured' do
            @resource_class.case_insensitive_keys = [:email]
            xhr :post, :create, @request_params
            assert_equal 200, response.status
          end

          test 'response should return failure status if not configured' do
            @resource_class.case_insensitive_keys = []
            xhr :post, :create, @request_params
            assert_equal 404, response.status
          end
        end
      end

      describe 'Using default_password_reset_url' do
        before do
          @resource = users(:confirmed_email_user)
          @redirect_url = 'http://ng-token-auth.dev'

          DeviseTokenAuth.default_password_reset_url = @redirect_url

          xhr :post, :create, {
            email:        @resource.email,
            redirect_url: @redirect_url
          }

          @mail = ActionMailer::Base.deliveries.last
          @resource.reload

          @sent_redirect_url = CGI.unescape(@mail.body.match(/redirect_url=([^&]*)&/)[1])
        end

        teardown do
          DeviseTokenAuth.default_password_reset_url = nil
        end

        test 'response should return success status' do
          assert_equal 200, response.status
        end

        test 'action should send an email' do
          assert @mail
        end

        test 'the email body should contain a link with redirect url as a query param' do
          assert_equal @redirect_url, @sent_redirect_url
        end
      end

      describe 'Using redirect_whitelist' do
        before do
          @resource = users(:confirmed_email_user)
          @good_redirect_url = Faker::Internet.url
          @bad_redirect_url = Faker::Internet.url
          DeviseTokenAuth.redirect_whitelist = [@good_redirect_url]
        end

        teardown do
          DeviseTokenAuth.redirect_whitelist = nil
        end

        test "request to whitelisted redirect should be successful" do
          xhr :post, :create, {
            email:        @resource.email,
            redirect_url: @good_redirect_url
          }

          assert_equal 200, response.status
        end

        test "request to non-whitelisted redirect should fail" do
          xhr :post, :create, {
            email:        @resource.email,
            redirect_url: @bad_redirect_url
          }

          assert_equal 403, response.status
        end
        test "request to non-whitelisted redirect should return error message" do
          xhr :post, :create, {
            email:        @resource.email,
            redirect_url: @bad_redirect_url
          }

          @data = JSON.parse(response.body)
          assert @data["errors"]
          assert_equal @data["errors"], [I18n.t("devise_token_auth.passwords.not_allowed_redirect_url", redirect_url: @bad_redirect_url)]
        end
      end

      describe "change password with current password required" do
        before do
          DeviseTokenAuth.check_current_password_before_update = :password
        end

        after do
          DeviseTokenAuth.check_current_password_before_update = false
        end

        describe 'success' do
          before do
            @auth_headers = @resource.create_new_auth_token
            request.headers.merge!(@auth_headers)
            @new_password = Faker::Internet.password
            @resource.update password: 'secret123', password_confirmation: 'secret123'

            xhr :put, :update, {
              password: @new_password,
              password_confirmation: @new_password,
              current_password: 'secret123'
            }

            @data = JSON.parse(response.body)
            @resource.reload
          end

          test "request should be successful" do
            assert_equal 200, response.status
          end
        end

        describe 'current password mismatch error' do
          before do
            @auth_headers = @resource.create_new_auth_token
            request.headers.merge!(@auth_headers)
            @new_password = Faker::Internet.password

            xhr :put, :update, {
              password: @new_password,
              password_confirmation: @new_password,
              current_password: 'not_very_secret321'
            }
          end

          test 'response should fail unauthorized' do
            assert_equal 422, response.status
          end
        end
      end

      describe "change password" do
        describe 'success' do
          before do
            @auth_headers = @resource.create_new_auth_token
            request.headers.merge!(@auth_headers)
            @new_password = Faker::Internet.password

            xhr :put, :update, {
              password: @new_password,
              password_confirmation: @new_password
            }

            @data = JSON.parse(response.body)
            @resource.reload
          end

          test "request should be successful" do
            assert_equal 200, response.status
          end

          test "request should return success message" do
            assert @data["data"]["message"]
            assert_equal @data["data"]["message"], I18n.t("devise_token_auth.passwords.successfully_updated")
          end

          test "new password should authenticate user" do
            assert @resource.valid_password?(@new_password)
          end
        end

        describe 'password mismatch error' do
          before do
            @auth_headers = @resource.create_new_auth_token
            request.headers.merge!(@auth_headers)
            @new_password = Faker::Internet.password

            xhr :put, :update, {
              password: 'chong',
              password_confirmation: 'bong'
            }
          end

          test 'response should fail' do
            assert_equal 422, response.status
          end
        end

        describe 'unauthorized user' do
          before do
            @auth_headers = @resource.create_new_auth_token
            @new_password = Faker::Internet.password

            xhr :put, :update, {
              password: @new_password,
              password_confirmation: @new_password
            }
          end

          test 'response should fail' do
            assert_equal 401, response.status
          end
        end
      end
    end

    describe "Alternate user class" do
      setup do
        @request.env['devise.mapping'] = Devise.mappings[:mang]
      end

      teardown do
        @request.env['devise.mapping'] = Devise.mappings[:user]
      end

      before do
        @resource = mangs(:confirmed_email_user)
        @redirect_url = 'http://ng-token-auth.dev'

        xhr :post, :create, {
          email:        @resource.email,
          redirect_url: @redirect_url
        }

        @mail = ActionMailer::Base.deliveries.last
        @resource.reload

        @mail_config_name  = CGI.unescape(@mail.body.match(/config=([^&]*)&/)[1])
        @mail_redirect_url = CGI.unescape(@mail.body.match(/redirect_url=([^&]*)&/)[1])
        @mail_reset_token  = @mail.body.match(/reset_password_token=(.*)\"/)[1]
      end

      test 'response should return success status' do
        assert_equal 200, response.status
      end

      test 'the email body should contain a link with reset token as a query param' do
        user = Mang.reset_password_by_token({
          reset_password_token: @mail_reset_token
        })

        assert_equal user.id, @resource.id
      end
    end

    describe 'unconfirmed user' do
      before do
        @resource = users(:unconfirmed_email_user)
        @redirect_url = 'http://ng-token-auth.dev'

        xhr :post, :create, {
          email:        @resource.email,
          redirect_url: @redirect_url
        }

        @mail = ActionMailer::Base.deliveries.last
        @resource.reload

        @mail_config_name  = CGI.unescape(@mail.body.match(/config=([^&]*)&/)[1])
        @mail_redirect_url = CGI.unescape(@mail.body.match(/redirect_url=([^&]*)&/)[1])
        @mail_reset_token  = @mail.body.match(/reset_password_token=(.*)\"/)[1]

        xhr :get, :edit, {
          reset_password_token: @mail_reset_token,
          redirect_url: @mail_redirect_url
        }

        @resource.reload
      end
    end
    describe 'unconfirmable user' do
      setup do
        @request.env['devise.mapping'] = Devise.mappings[:unconfirmable_user]
      end

      teardown do
        @request.env['devise.mapping'] = Devise.mappings[:user]
      end

      before do
        @resource = unconfirmable_users(:user)
        @redirect_url = 'http://ng-token-auth.dev'

        xhr :post, :create, {
          email:        @resource.email,
          redirect_url: @redirect_url
        }

        @mail = ActionMailer::Base.deliveries.last
        @resource.reload

        @mail_config_name  = CGI.unescape(@mail.body.match(/config=([^&]*)&/)[1])
        @mail_redirect_url = CGI.unescape(@mail.body.match(/redirect_url=([^&]*)&/)[1])
        @mail_reset_token  = @mail.body.match(/reset_password_token=(.*)\"/)[1]

        xhr :get, :edit, {
          reset_password_token: @mail_reset_token,
          redirect_url: @mail_redirect_url
        }

        @resource.reload
      end
    end

    describe 'alternate user type' do
      before do
        @resource         = users(:confirmed_email_user)
        @redirect_url = 'http://ng-token-auth.dev'
        @config_name  = "altUser"

        xhr :post, :create, {
          email:        @resource.email,
          redirect_url: @redirect_url,
          config_name:  @config_name
        }

        @mail = ActionMailer::Base.deliveries.last
        @resource.reload

        @mail_config_name  = CGI.unescape(@mail.body.match(/config=([^&]*)&/)[1])
        @mail_redirect_url = CGI.unescape(@mail.body.match(/redirect_url=([^&]*)&/)[1])
        @mail_reset_token  = @mail.body.match(/reset_password_token=(.*)\"/)[1]
      end

      test 'config_name param is included in the confirmation email link' do
        assert_equal @config_name, @mail_config_name
      end
    end
  end
end
