Feature: Manage Deployments
  In order to manage my cloud infrastructure
  As a user
  I want to manage my deployments

  Background:
    Given I am an authorised user
    And I am logged in

  Scenario: List deployments
    Given there is a deployment named "MySQL Cluster" belonging to "Databases" owned by "bob"
    And I am on the pools page
    When I follow link with ID "filter_view"
    And I follow "Deployments" within "#details-view"
    Then I should see "MySQL Cluster"
    And I should see "bob"

  Scenario: List deployments over XHR
    Given there is a deployment named "MySQL Cluster" belonging to "Databases" owned by "bob"
    And I am on the pools page
    And I request XHR
    When I follow link with ID "filter_view"
    And I follow "Deployments"
    Then I should see "MySQL Cluster"
    And I should see "bob"

  Scenario: Launch new deployment
    Given a pool "mockpool" exists
    And there is "front_hwp1" conductor hardware profile
    And there is "front_hwp2" conductor hardware profile
    When I am viewing the pool "mockpool"
    And I follow "New Deployment"
    Then I should see "New Deployment in mockpool"
    When I fill in "deployable_url" with "http://localhost/deployables/deployable1.xml"
    When I fill in "deployment_name" with "mynewdeployment"
    When I press "Next"
    Then I should see "Launch Summary"
    When I press "Launch"
    Then I should see "Deployment launched"
    Then I should see "mynewdeployment Deployment"

  Scenario: Launch new deployment over XHR
    Given a pool "mockpool" exists
    And there is "front_hwp1" conductor hardware profile
    And there is "front_hwp2" conductor hardware profile
    When I am viewing the pool "mockpool"
    And I request XHR
    And I follow "New Deployment"
    Then I should get back a partial
    Then I should see "New Deployment in mockpool"
    When I fill in "deployable_url" with "http://localhost/deployables/deployable1.xml"
    When I fill in "deployment_name" with "mynewdeployment"
    When I press "Next"
    Then I should see "Launch Summary"
    When I press "Launch"
    Then I should see "Created"
    Then I should see "mynewdeployment"

  Scenario: Stop deployments
    Given there is a deployment named "testdeployment" belonging to "testdeployable" owned by "testuser"
    When I go to the deployments page
    Then I should see "testdeployment"
    When I check "testdeployment" deployment
    And I press "Stop"
    Then I should see "testdeployment"

  Scenario: Stop a deployment over XHR
    Given there is a deployment named "testdeployment" belonging to "testdeployable" owned by "testuser"
    And I request XHR
    When I go to the deployments page
    Then I should get back a partial
    And I should see "testdeployment"
    When I check "testdeployment" deployment
    And I press "Stop"
    Then I should get back a partial
    And I should see "testdeployment"

  Scenario: Show operational status of deployment
    Given there is a deployment named "testdeployment" belonging to "testdeployable" owned by "testuser"
    When I am on the deployments page
    And I follow "testdeployment"
    Then I should see "testdeployment"

  Scenario: Edit deployment name
    Given there is a deployment named "Hudson" belonging to "QA Infrastructure" owned by "joe"
    When I go to Hudson's edit deployment page
    Then I should see "Edit deployment"
    When I fill in "name" with "Jenkins"
    And I press "Save"
    Then I should be on Jenkins's deployment page
    And I should see "Jenkins"

  Scenario: Edit deployment name using XHR
    Given there is a deployment named "Hudson" belonging to "QA Infrastructure" owned by "joe"
    And I request XHR
    When I go to Hudson's edit deployment page
    Then I should get back a partial
    And I should see "Edit deployment"
    When I fill in "name" with "Jenkins"
    And I press "Save"
    Then I should get back a partial
    And I should be on Jenkins's deployment page
    And I should see "Jenkins"

  Scenario: View all deployments in JSON format
    And there are 2 deployments
    And I accept JSON
    When I go to the deployments page
    Then I should see 2 deployments in JSON format

  Scenario: View a deployment in JSON format
    And a deployment "mockdeployment" exists
    And I accept JSON
    When I am viewing the deployment "mockdeployment"
    Then I should see deployment "mockdeployment" in JSON format

  Scenario: View a deployment via XHR
    And a deployment "mockdeployment" exists
    And I request XHR
    When I am viewing the deployment "mockdeployment"
    Then I should get back a partial
    And I should see "mockdeployment"

  Scenario: Create a deployment and get JSON response
    And I accept JSON
    When I create a deployment
    Then I should get back a deployment in JSON format

  Scenario: Create a deployment and get XHR response
    And I request XHR
    When I create a deployment
    Then I should get back a partial

  Scenario: Stop a deployment
    Given a deployment "mockdeployment" exists
    And I accept JSON
    When I stop "mockdeployment" deployment
    Then I should get back JSON object with success and errors
