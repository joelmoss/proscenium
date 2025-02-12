# frozen_string_literal: true

Fruit.delete_all
Fruit.insert_all([
                   { name: 'apple' },
                   { name: 'orange' },
                   { name: 'pear' },
                   { name: 'banana' },
                   { name: 'grape' },
                   { name: 'kiwi' },
                   { name: 'watermelon' },
                   { name: 'pineapple' },
                   { name: 'strawberry' }
                 ])
