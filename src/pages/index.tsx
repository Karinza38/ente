import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/router';
import Card from 'react-bootstrap/Card';
import Form from 'react-bootstrap/Form';
import FormControl from 'react-bootstrap/FormControl';
import Button from 'react-bootstrap/Button';
import constants from 'utils/strings/constants';
import { Formik, FormikHelpers } from 'formik';
import * as Yup from 'yup';
import { getOtt } from 'services/userService';
import Container from 'components/Container';
import { setData, LS_KEYS, getData } from 'utils/storage/localStorage';

interface formValues {
    email: string;
}

export default function Home() {
    const [loading, setLoading] = useState(false);
    const router = useRouter();

    useEffect(() => {
        const user = getData(LS_KEYS.USER);
        if (user?.email) {
            router.push('/verify');
        }
    }, []);

    const loginUser = async ({ email }: formValues, { setFieldError }: FormikHelpers<formValues>) => {
        try {
            setLoading(true);
            await getOtt(email);
            setData(LS_KEYS.USER, { email });
            router.push('/verify');
        } catch (e) {
            setFieldError('email', `${constants.UNKNOWN_ERROR} ${e.message}`);
        }
        setLoading(false);
    }

    return (
        <Container>
            <Card style={{ minWidth: '300px' }}>
                <Card.Body>
                    <Card.Title>{constants.LOGIN}</Card.Title>
                    <Formik<formValues>
                        initialValues={{email: ''}}
                        validationSchema={Yup.object().shape({
                            email: Yup.string()
                                .email(constants.EMAIL_ERROR)
                                .required(constants.REQUIRED)
                        })}
                        onSubmit={loginUser}
                    >
                        {({values, errors, touched, handleChange, handleBlur, handleSubmit}) => (
                            <Form noValidate onSubmit={handleSubmit}>
                                <Form.Group controlId="formBasicEmail">
                                    <Form.Label>{constants.EMAIL}</Form.Label>
                                    <Form.Control
                                        type="email"
                                        placeholder={constants.ENTER_EMAIL}
                                        value={values.email}
                                        onChange={handleChange('email')}
                                        onBlur={handleBlur('email')}
                                        isInvalid={Boolean(touched.email && errors.email)}
                                        disabled={loading}
                                    />
                                    <FormControl.Feedback type="invalid">
                                        {errors.email}
                                    </FormControl.Feedback>
                                    <Form.Text className="text-muted">
                                        {constants.EMAIL_DISCLAIMER}
                                    </Form.Text>
                                </Form.Group>
                                <Button
                                    variant="primary" type="submit" block
                                    disabled={loading}
                                >
                                    {constants.SUBMIT}
                                </Button>
                            </Form>
                        )}
                    </Formik>
                </Card.Body>
            </Card>
        </Container>
    )
}
