import 'package:attendance_planner/faculty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = [
    Teacher('Prof. Sandip Singh', 'sandip.singh.gf@iimmumbai.ac.in'),
    Teacher('Prof. Vikram Aithal', 'vikram.aithal.gf@iimmumbai.ac.in'),
    Teacher('Prof. Amiya Ranjan Bhowmick', 'amiya.ranjan.gf@iimmumbai.ac.in'),
    Teacher('Prof. Juvvala Rambabu', 'rambabujuvvala@iimmumbai.ac.in'),
    Teacher('Prof. M. Venkateshwarlu', 'venkat@iimmumbai.ac.in'),
    Teacher('Prof. Manoj Kumar Tiwari', 'mkt09@iimmumbai.ac.in'),
    Teacher('Prof. Ravindra Gokhale', 'rgokhale@iimmumbai.ac.in'),
    Teacher('Prof. Rofin T M', 'rofintm@iimmumbai.ac.in'),
    Teacher(
        'Dr. Sorbojeet Chatterjee', 'sorbojeet.chatterjee.gf@iimmumbai.ac.in'),
    Teacher('Prof. Srishti Kumar', 'srishtik@iimmumbai.ac.in'),
    Teacher('Prof. Jasashwi Mandal', 'jasashwi.mandal@iimmumbai.ac.in'),
  ];
  String? email(String n) => findTeacher(n, dir)?.email;

  test('names as the portal and the timetable write them', () {
    expect(email('Prof . Sandip Singh (Guest Faculty)'),
        'sandip.singh.gf@iimmumbai.ac.in');
    expect(email('Prof.Vikram Aithal'), 'vikram.aithal.gf@iimmumbai.ac.in');
    expect(email('Prof.J.Rambabu'), 'rambabujuvvala@iimmumbai.ac.in');
    expect(email('Prof. Rofin T.M.'), 'rofintm@iimmumbai.ac.in');
    expect(email('Prof. M. Venkateshwarlu'), 'venkat@iimmumbai.ac.in');
    expect(
        email('Prof. Ravindra Shridhar Gokhale'), 'rgokhale@iimmumbai.ac.in');
    expect(email('Prof.Sorbojeet Chatterjee'),
        'sorbojeet.chatterjee.gf@iimmumbai.ac.in');
    expect(email('Prof. Jasashwi Mandal (Theory)'),
        'jasashwi.mandal@iimmumbai.ac.in');
  });

  test('a shared word is not enough to pick someone', () {
    expect(email('Prof. Srishti Kumar'), 'srishtik@iimmumbai.ac.in');
    expect(email('Prof. Manoj Kumar Tiwari'), 'mkt09@iimmumbai.ac.in');
    expect(email('Prof. Kumar'), isNull); // two teachers are called Kumar
    expect(email('HPE'), isNull);
    expect(email('Trainer 1 HPE'), isNull);
  });

  test('several teachers in one field, and the greeting', () {
    expect(
        splitTeachers(
            'Prof. Rofin T.M., Prof. Juvvala Rambabu, Prof. Sorbojeet Chatterjee (Guest Faculty)'),
        [
          'Prof. Rofin T.M.',
          'Prof. Juvvala Rambabu',
          'Prof. Sorbojeet Chatterjee (Guest Faculty)'
        ]);
    expect(
        greetingName('Dr. Sorbojeet Chatterjee'), 'Prof. Sorbojeet Chatterjee');
    expect(greetingName('Prof. Rofin T M'), 'Prof. Rofin T M');
  });
}
