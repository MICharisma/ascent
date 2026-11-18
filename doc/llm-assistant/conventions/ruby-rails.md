# Ruby on Rails Conventions

## Browsing
- You can access the application at http://ascent.test
- Server restarts are usually only needed after adding a gem, editing files in the config folder, or updating files in lib.
- I will try to stay logged in on your browser to simplify the devise situation.
- Remember to review the development log as the fastest way to review context.
- When browsing results in an error, this is a hint about something that could become part of the test suite, and it should be noted in testing.md in the test prospectus section.

## Testing
- Use Rspec for testing
- Use FactoryBot for factories
- Use Shoulda Matchers for matchers
- Regarding factories, it would be typical to define them with minimal specification, and to use just one for each required configuration.  This project will, on the contrary, often define multiple options for each factory, and use highly-descriptive data to populate their attributes.  This will serve as a form of documentation for open-source developers and political scientists who are curious about the code.

## Controllers
- Extract a service object only when the behavior needs one
- However, most of the methods necessary to implement the logic can be defined on the relevant models
- Since Phlex templates are being used, the variables set in controller actions do not need to be instance variables.  In fact, local variables are preferred.  In most cases, the named arguments for the Phlex template will match the names of the variables being set - and in that case, the template will be able to infer the objects being passed to it.

## Models
- ActiveRecord macros do not need to be tested in the Rspec suite
- For compound interactions, it can still be useful to establish some specs to illustrate the expected behavior

## View Helpers
- The optimal approach to Rails development makes heavy use of view helpers to encapsulate every aspect of the markup structure.
- Helpers will often be simple enough to be reused in different contexts, and with different classes of arguments.  However, this flexibility should not be supported until it is ready to be used.  Once a new presentation aspect is ready to make use of an existing helper, it can either call it as is, or rename it to suit the expanding generality.  It would also be permissable to create an alias for the method.
- It's fine to create a helper to encapsulate some structure or logic, even if that helper will only be called in one place.  This still makes the code more readable, testable, and maintainable.
- Most of the time, the helper's name can be the same as the classname of its outermost HTML element.  However, the CSS will use dashes in place of underscores.
- One of the primary roles of view helpers is to establish the structure of HTML elements, and the nesting thereof.  Rails has several conventions that are suited to this task.  We will use two of them: 
- safe_join can be called on an array of variables or methods, when nesting them in a container is not necessary, or when they can be passed as the first argument to a tag method.
- the other technique is to call tag helpers with a block, and then concatenate the helpers called inside the block.  This technique preserves the sequence in which tags will be seen in the browser.  It requires a couple of extra steps: all methods on either side of the + must use parentheses; and certain objects that get added to the concatenation will need a call to .html_safe.

## Phlex Templates
- Phlex templates need an initializer to set instance variables from arguments passed to the template.
- The objects being passed to the template can be inferred if they are available as either local variables or methods.

## Ruby Style
- Much of the time, parentheses are not necessary in Ruby.  This can be a good indication of how much logic to put on a single line.
- However, calling methods directly on a result is usually better than storing it in a variable if that variable will only be used once.
- Creating another method to encapsulate the needed logic is helpful, for example when if statements or case statements are part of the setup.
- While handling the objects passed in as arguments, do not begin by checking if they are nil or testing which format of data structure they contain.  Those levels of flexibility can be added once we begin to use them in that way.
